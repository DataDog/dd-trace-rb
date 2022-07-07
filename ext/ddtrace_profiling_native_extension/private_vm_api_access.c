#include "extconf.h"

// This file exports functions used to access private Ruby VM APIs and internals.
// To do this, it imports a few VM internal (private) headers.
//
// **Important Note**: Our medium/long-term plan is to stop relying on all private Ruby headers, and instead request and
// contribute upstream changes so that they become official public VM APIs.
//
// In the meanwhile, be very careful when changing things here :)

#ifdef RUBY_MJIT_HEADER
  // Pick up internal structures from the private Ruby MJIT header file
  #include RUBY_MJIT_HEADER
#else
  // On older Rubies, use a copy of the VM internal headers shipped in the debase-ruby_core_source gem
  #include <vm_core.h>
  #include <iseq.h>
#endif

#define PRIVATE_VM_API_ACCESS_SKIP_RUBY_INCLUDES
#include "private_vm_api_access.h"

// MRI has a similar rb_thread_ptr() function which we can't call it directly
// because Ruby does not expose the thread_data_type publicly.
// Instead, we have our own version of that function, and we lazily initialize the thread_data_type pointer
// from a known-correct object: the current thread.
//
// Note that beyond returning the rb_thread_struct*, rb_check_typeddata() raises an exception
// if the argument passed in is not actually a `Thread` instance.
static inline rb_thread_t *thread_struct_from_object(VALUE thread) {
  static const rb_data_type_t *thread_data_type = NULL;
  if (thread_data_type == NULL) thread_data_type = RTYPEDDATA_TYPE(rb_thread_current());

  return (rb_thread_t *) rb_check_typeddata(thread, thread_data_type);
}

rb_nativethread_id_t pthread_id_for(VALUE thread) {
  // struct rb_native_thread was introduced in Ruby 3.2 (preview2): https://github.com/ruby/ruby/pull/5836
  #ifndef NO_RB_NATIVE_THREAD
    return thread_struct_from_object(thread)->nt->thread_id;
  #else
    return thread_struct_from_object(thread)->thread_id;
  #endif
}

// Returns the stack depth by using the same approach as rb_profile_frames and backtrace_each: get the positions
// of the end and current frame pointers and subtracting them.
ptrdiff_t stack_depth_for(VALUE thread) {
  #ifndef USE_THREAD_INSTEAD_OF_EXECUTION_CONTEXT // Modern Rubies
    const rb_execution_context_t *ec = thread_struct_from_object(thread)->ec;
  #else // Ruby < 2.5
    const rb_thread_t *ec = thread_struct_from_object(thread);
  #endif

  const rb_control_frame_t *cfp = ec->cfp, *end_cfp = RUBY_VM_END_CONTROL_FRAME(ec);

  if (end_cfp == NULL) return 0;

  // Skip dummy frame, as seen in `backtrace_each` (`vm_backtrace.c`) and our custom rb_profile_frames
  // ( https://github.com/ruby/ruby/blob/4bd38e8120f2fdfdd47a34211720e048502377f1/vm_backtrace.c#L890-L914 )
  end_cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);

  return end_cfp <= cfp ? 0 : end_cfp - cfp - 1;
}

// This was renamed in Ruby 3.2
#if !defined(ccan_list_for_each) && defined(list_for_each)
  #define ccan_list_for_each list_for_each
#endif

#ifndef USE_LEGACY_LIVING_THREADS_ST // Ruby > 2.1
// Tries to match rb_thread_list() but that method isn't accessible to extensions
VALUE ddtrace_thread_list(void) {
  VALUE result = rb_ary_new();
  rb_thread_t *thread = NULL;

  // Ruby 3 Safety: Our implementation is inspired by `rb_ractor_thread_list` BUT that method wraps the operations below
  // with `RACTOR_LOCK` and `RACTOR_UNLOCK`.
  //
  // This initially made me believe that one MUST grab the ractor lock (which is different from the ractor-scoped Global
  // VM Lock) in able to iterate the `threads.set`. This turned out not to be the case: upon further study of the VM
  // codebase in 3.2-master, 3.1 and 3.0, there's quite a few places where `threads.set` is accessed without grabbing
  // the ractor lock: `ractor_mark` (ractor.c), `thgroup_list` (thread.c), `rb_check_deadlock` (thread.c), etc.
  //
  // I suspect the design in `rb_ractor_thread_list` may be done that way to perhaps in the future expose it to be
  // called from a different Ractor, but I'm not sure...
  #ifdef HAVE_RUBY_RACTOR_H
    rb_ractor_t *current_ractor = GET_RACTOR();
    ccan_list_for_each(&current_ractor->threads.set, thread, lt_node) {
  #else
    rb_vm_t *vm = thread_struct_from_object(rb_thread_current())->vm;
    list_for_each(&vm->living_threads, thread, vmlt_node) {
  #endif
      switch (thread->status) {
        case THREAD_RUNNABLE:
        case THREAD_STOPPED:
        case THREAD_STOPPED_FOREVER:
          rb_ary_push(result, thread->self);
        default:
          break;
      }
    }

  return result;
}
#else // USE_LEGACY_LIVING_THREADS_ST
static int ddtrace_thread_list_each(st_data_t thread_object, st_data_t _value, void *result_object);

// Alternative ddtrace_thread_list implementation for Ruby 2.1. In this Ruby version, living threads were stored in a
// hashmap (st) instead of a list.
VALUE ddtrace_thread_list() {
  VALUE result = rb_ary_new();
  st_foreach(thread_struct_from_object(rb_thread_current())->vm->living_threads, ddtrace_thread_list_each, result);
  return result;
}

static int ddtrace_thread_list_each(st_data_t thread_object, st_data_t _value, void *result_object) {
  VALUE result = (VALUE) result_object;
  rb_thread_t *thread = thread_struct_from_object((VALUE) thread_object);
  switch (thread->status) {
    case THREAD_RUNNABLE:
    case THREAD_STOPPED:
    case THREAD_STOPPED_FOREVER:
      rb_ary_push(result, thread->self);
    default:
      break;
  }
  return ST_CONTINUE;
}
#endif // USE_LEGACY_LIVING_THREADS_ST

bool is_thread_alive(VALUE thread) {
  return thread_struct_from_object(thread)->status != THREAD_KILLED;
}

// -----------------------------------------------------------------------------
// The sources below are modified versions of code extracted from the Ruby project.
// Each function is annotated with its origin, why we imported it, and the changes made.
//
// The Ruby project copyright and license follow:
// -----------------------------------------------------------------------------
// Copyright (C) 1993-2013 Yukihiro Matsumoto. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
// OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.

#ifndef USE_LEGACY_RB_PROFILE_FRAMES // Modern Rubies

// Taken from upstream vm_core.h at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 2004-2007 Koichi Sasada
// to support our custom rb_profile_frames (see below)
// Modifications: None
#define ISEQ_BODY(iseq) ((iseq)->body)

// Taken from upstream vm_backtrace.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
// to support our custom rb_profile_frames (see below)
// Modifications: None
inline static int
calc_pos(const rb_iseq_t *iseq, const VALUE *pc, int *lineno, int *node_id)
{
    VM_ASSERT(iseq);
    VM_ASSERT(ISEQ_BODY(iseq));
    VM_ASSERT(ISEQ_BODY(iseq)->iseq_encoded);
    VM_ASSERT(ISEQ_BODY(iseq)->iseq_size);
    if (! pc) {
        if (ISEQ_BODY(iseq)->type == ISEQ_TYPE_TOP) {
            VM_ASSERT(! ISEQ_BODY(iseq)->local_table);
            VM_ASSERT(! ISEQ_BODY(iseq)->local_table_size);
            return 0;
        }
        if (lineno) *lineno = FIX2INT(ISEQ_BODY(iseq)->location.first_lineno);
#ifdef USE_ISEQ_NODE_ID
        if (node_id) *node_id = -1;
#endif
        return 1;
    }
    else {
        ptrdiff_t n = pc - ISEQ_BODY(iseq)->iseq_encoded;
        VM_ASSERT(n <= ISEQ_BODY(iseq)->iseq_size);
        VM_ASSERT(n >= 0);
        ASSUME(n >= 0);
        size_t pos = n; /* no overflow */
        if (LIKELY(pos)) {
            /* use pos-1 because PC points next instruction at the beginning of instruction */
            pos--;
        }
#if VMDEBUG && defined(HAVE_BUILTIN___BUILTIN_TRAP)
        else {
            /* SDR() is not possible; that causes infinite loop. */
            rb_print_backtrace();
            __builtin_trap();
        }
#endif
        if (lineno) *lineno = rb_iseq_line_no(iseq, pos);
#ifdef USE_ISEQ_NODE_ID
        if (node_id) *node_id = rb_iseq_node_id(iseq, pos);
#endif
        return 1;
    }
}

// Taken from upstream vm_backtrace.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
// to support our custom rb_profile_frames (see below)
// Modifications: None
inline static int
calc_lineno(const rb_iseq_t *iseq, const VALUE *pc)
{
    int lineno;
    if (calc_pos(iseq, pc, &lineno, NULL)) return lineno;
    return 0;
}

// Taken from upstream vm_backtrace.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
// Modifications:
// * Renamed rb_profile_frames => ddtrace_rb_profile_frames
// * Add thread argument
// * Add is_ruby_frame argument
// * Removed `if (lines)` tests -- require/assume that like `buff`, `lines` is always specified
// * Support Ruby < 2.5 by using rb_thread_t instead of rb_execution_context_t (which did not exist and was just
//   part of rb_thread_t)
// * Support Ruby < 2.4 by using `RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)` instead of `VM_FRAME_RUBYFRAME_P(cfp)`.
//   Given that the Ruby 2.3 version of `rb_profile_frames` did not support native methods and thus did not need this
//   check, how did I figure out what to replace it with? I did it by looking at other places in the VM code where the
//   code looks exactly the same but Ruby 2.4 uses `VM_FRAME_RUBYFRAME_P` whereas Ruby 2.3 used `RUBY_VM_NORMAL_ISEQ_P`.
//   Examples of these are `errinfo_place` in `eval.c`, `rb_vm_get_ruby_level_next_cfp` (among others) in `vm.c`, etc.
// * Skip dummy frame that shows up in main thread
// * Add `end_cfp == NULL` and `end_cfp <= cfp` safety checks. These are used in a bunch of places in
//   `vm_backtrace.c` (`backtrace_each`, `backtrace_size`, `rb_ec_partial_backtrace_object`) but are conspicuously
//   absent from `rb_profile_frames`. Oversight?
// * Distinguish between `end_cfp == NULL` (dead thread or some other error, returns 0) and `end_cfp <= cfp`
//   (alive thread which may just be executing native code and has not pushed anything on the Ruby stack, returns
//   PLACEHOLDER_STACK_IN_NATIVE_CODE). See comments on `record_placeholder_stack_in_native_code` for more details.
// * Skip frames where `cfp->iseq && !cfp->pc`. These seem to be internal and are skipped by `backtrace_each` in
//   `vm_backtrace.c`.
// * Check thread status and do not sample if thread has been killed.
// * Match Ruby reference stack trace APIs that use the iseq instead of the callable method entry to get information
//   for iseqs created from calls to `eval` and `instance_eval`. This makes it so that `rb_profile_frame_path` on
//   the `VALUE` returned by rb_profile_frames returns `(eval)` instead of the path of the file where the `eval`
//   was called from.
//
// **IMPORTANT: WHEN CHANGING THIS FUNCTION, CONSIDER IF THE SAME CHANGE ALSO NEEDS TO BE MADE TO THE VARIANT FOR
// RUBY 2.2 AND BELOW WHICH IS ALSO PRESENT ON THIS FILE**
//
// What is rb_profile_frames?
// `rb_profile_frames` is a Ruby VM debug API added for use by profilers for sampling the stack trace of a Ruby thread.
// Its main other user is the stackprof profiler: https://github.com/tmm1/stackprof .
//
// Why do we need a custom version of rb_profile_frames?
//
// There are a few reasons:
// 1. To backport improved behavior to older Rubies. Prior to Ruby 3.0 (https://github.com/ruby/ruby/pull/3299),
//    rb_profile_frames skipped CFUNC frames, aka frames that are implemented with native code, and thus the resulting
//    stacks were quite incomplete as a big part of the Ruby standard library is implemented with native code.
//
// 2. To extend this function to work with any thread. The upstream rb_profile_frames function only targets the current
//    thread, and to support wall-clock profiling we require sampling other threads. This is only safe because of the
//    Global VM Lock. (We don't yet support sampling Ractors beyond the main one; we'll need to find a way to do it
//    safely first.)
//
// 3. To get more information out of the Ruby VM. The Ruby VM has a lot more information than is exposed through
//    rb_profile_frames, and by making our own copy of this function we can extract more of this information.
//    See for backtracie gem (https://github.com/ivoanjo/backtracie) for an exploration of what can potentially be done.
//
// 4. Because we haven't yet submitted patches to upstream Ruby. As with any changes on the `private_vm_api_access.c`,
//    our medium/long-term plan is to contribute upstream changes and make it so that we don't need any of this
//    on modern Rubies.
//
// 5. To make rb_profile_frames behave more like the Ruby-level reference stack trace APIs (`Thread#backtrace_locations`
//    and friends). We've found quite a few situations where the data from rb_profile_frames and the reference APIs
//    disagree, and quite a few of them seem oversights/bugs (speculation from my part) rather than deliberate
//    decisions.
int ddtrace_rb_profile_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines, bool* is_ruby_frame)
{
    int i;
    // Modified from upstream: Instead of using `GET_EC` to collect info from the current thread,
    // support sampling any thread (including the current) passed as an argument
    rb_thread_t *th = thread_struct_from_object(thread);
#ifndef USE_THREAD_INSTEAD_OF_EXECUTION_CONTEXT // Modern Rubies
    const rb_execution_context_t *ec = th->ec;
#else // Ruby < 2.5
    const rb_thread_t *ec = th;
#endif
    const rb_control_frame_t *cfp = ec->cfp, *end_cfp = RUBY_VM_END_CONTROL_FRAME(ec);
    const rb_callable_method_entry_t *cme;

    // `vm_backtrace.c` includes this check in several methods, and I think this happens on either dead or newly-created
    // threads, but I'm not entirely sure
    if (end_cfp == NULL) return 0;

    // Avoid sampling dead threads
    if (th->status == THREAD_KILLED) return 0;

    // Fix: Skip dummy frame that shows up in main thread.
    //
    // According to a comment in `backtrace_each` (`vm_backtrace.c`), there's two dummy frames that we should ignore
    // at the base of every thread's stack.
    // (see https://github.com/ruby/ruby/blob/4bd38e8120f2fdfdd47a34211720e048502377f1/vm_backtrace.c#L890-L914 )
    //
    // One is being pointed to by `RUBY_VM_END_CONTROL_FRAME(ec)`, and so we need to advance to the next one, and
    // reaching it will be used as a condition to break out of the loop below.
    //
    // Note that in `backtrace_each` there's two calls to `RUBY_VM_NEXT_CONTROL_FRAME`, but the loop bounds there
    // are computed in a different way, so the two calls really are equivalent to one here.
    end_cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);

    // See comment on `record_placeholder_stack_in_native_code` for a full explanation of what this means (and why we don't just return 0)
    if (end_cfp <= cfp) return PLACEHOLDER_STACK_IN_NATIVE_CODE;

    for (i=0; i<limit && cfp != end_cfp;) {
        if (cfp->iseq && !cfp->pc) {
          // Fix: Do nothing -- this frame should not be used
          //
          // rb_profile_frames does not do this check, but `backtrace_each` (`vm_backtrace.c`) does. This frame is not
          // exposed by the Ruby backtrace APIs and for now we want to match its behavior 1:1
        }
#ifndef USE_ISEQ_P_INSTEAD_OF_RUBYFRAME_P // Modern Rubies
        else if (VM_FRAME_RUBYFRAME_P(cfp)) {
#else // Ruby < 2.4
        else if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
#endif
            if (start > 0) {
                start--;
                continue;
            }

            /* record frame info */
            cme = rb_vm_frame_method_entry(cfp);

            if (cme && cme->def->type == VM_METHOD_TYPE_ISEQ &&
              // Fix: Do not use callable method entry when iseq is for an eval.
              // TL;DR: This fix is needed for us to match the Ruby reference API information in the
              // "when sampling an eval/instance eval inside an object" spec.
              //
              // Longer note:
              // When a frame is a ruby frame (VM_FRAME_RUBYFRAME_P above), we can get information about it
              // by introspecting both the callable method entry, as well as the iseq directly.
              // Often they match... but sometimes they provide different info (as in the "iseq for an eval" situation
              // here).
              // If my reading of vm_backtrace.c is correct, the actual Ruby stack trace API **never** uses the
              // callable method entry for Ruby frames, but only for VM_METHOD_TYPE_CFUNC (see `backtrace_each` method
              // on that file).
              // So... why does `rb_profile_frames` do something different? Is it a bug? Is it because it exposes
              // more information than the Ruby stack frame API?
              // As a final note, the `backtracie` gem (https://github.com/ivoanjo/backtracie) can be used to introspect
              // the full metadata provided by both the callable method entry as well as the iseq, and is really useful
              // to debug and learn more about these differences.
              cfp->iseq->body->type != ISEQ_TYPE_EVAL) {
                buff[i] = (VALUE)cme;
            }
            else {
                buff[i] = (VALUE)cfp->iseq;
            }

            lines[i] = calc_lineno(cfp->iseq, cfp->pc);
            is_ruby_frame[i] = true;
            i++;
        }
        else {
            cme = rb_vm_frame_method_entry(cfp);
            if (cme && cme->def->type == VM_METHOD_TYPE_CFUNC) {
                buff[i] = (VALUE)cme;
                lines[i] = 0;
                is_ruby_frame[i] = false;
                i++;
            }
        }
        cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }

    return i;
}

#ifdef USE_BACKPORTED_RB_PROFILE_FRAME_METHOD_NAME

// Taken from upstream vm_backtrace.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
// to support our custom rb_profile_frame_method_name (see below)
// Modifications: None
static VALUE
id2str(ID id)
{
    VALUE str = rb_id2str(id);
    if (!str) return Qnil;
    return str;
}
#define rb_id2str(id) id2str(id)

// Taken from upstream vm_backtrace.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
// to support our custom rb_profile_frame_method_name (see below)
// Modifications: None
static const rb_iseq_t *
frame2iseq(VALUE frame)
{
    if (NIL_P(frame)) return NULL;

    if (RB_TYPE_P(frame, T_IMEMO)) {
    switch (imemo_type(frame)) {
      case imemo_iseq:
        return (const rb_iseq_t *)frame;
      case imemo_ment:
        {
        const rb_callable_method_entry_t *cme = (rb_callable_method_entry_t *)frame;
        switch (cme->def->type) {
          case VM_METHOD_TYPE_ISEQ:
            return cme->def->body.iseq.iseqptr;
          default:
            return NULL;
        }
        }
      default:
        break;
    }
    }
    rb_bug("frame2iseq: unreachable");
}

// Taken from upstream vm_backtrace.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
// to support our custom rb_profile_frame_method_name (see below)
// Modifications: None
static const rb_callable_method_entry_t *
cframe(VALUE frame)
{
    if (NIL_P(frame)) return NULL;

    if (RB_TYPE_P(frame, T_IMEMO)) {
    switch (imemo_type(frame)) {
      case imemo_ment:
            {
        const rb_callable_method_entry_t *cme = (rb_callable_method_entry_t *)frame;
        switch (cme->def->type) {
          case VM_METHOD_TYPE_CFUNC:
            return cme;
          default:
            return NULL;
        }
            }
          default:
            return NULL;
        }
    }

    return NULL;
}

// Taken from upstream vm_backtrace.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
//
// Ruby 3.0 finally added support for showing CFUNC frames (frames for methods written using native code)
// in stack traces gathered via `rb_profile_frames` (https://github.com/ruby/ruby/pull/3299).
// To access this information on older Rubies, beyond using our custom `ddtrace_rb_profile_frames` above, we also need
// to backport the Ruby 3.0+ version of `rb_profile_frame_method_name`.
//
// Modifications:
// * Renamed rb_profile_frame_method_name => ddtrace_rb_profile_frame_method_name
VALUE
ddtrace_rb_profile_frame_method_name(VALUE frame)
{
    const rb_callable_method_entry_t *cme = cframe(frame);
    if (cme) {
        ID mid = cme->def->original_id;
        return id2str(mid);
    }
    const rb_iseq_t *iseq = frame2iseq(frame);
    return iseq ? rb_iseq_method_name(iseq) : Qnil;
}

#endif // USE_BACKPORTED_RB_PROFILE_FRAME_METHOD_NAME

// Support code for older Rubies that cannot use the MJIT header
#ifndef RUBY_MJIT_HEADER

#define MJIT_STATIC // No-op on older Rubies

// Taken from upstream include/ruby/backward/2/bool.h at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) Ruby developers <ruby-core@ruby-lang.org>
// to support our custom rb_profile_frames (see above)
// Modifications: None
#ifndef FALSE
# define FALSE false
#elif FALSE
# error FALSE must be false
#endif

#ifndef TRUE
# define TRUE true
#elif ! TRUE
# error TRUE must be true
#endif

// Taken from upstream vm_insnhelper.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
// Copyright (C) 2007 Koichi Sasada
// to support our custom rb_profile_frames (see above)
// Modifications: None
static rb_callable_method_entry_t *
check_method_entry(VALUE obj, int can_be_svar)
{
    if (obj == Qfalse) return NULL;

#if VM_CHECK_MODE > 0
    if (!RB_TYPE_P(obj, T_IMEMO)) rb_bug("check_method_entry: unknown type: %s", rb_obj_info(obj));
#endif

    switch (imemo_type(obj)) {
      case imemo_ment:
        return (rb_callable_method_entry_t *)obj;
      case imemo_cref:
        return NULL;
      case imemo_svar:
        if (can_be_svar) {
            return check_method_entry(((struct vm_svar *)obj)->cref_or_me, FALSE);
        }
      default:
#if VM_CHECK_MODE > 0
        rb_bug("check_method_entry: svar should not be there:");
#endif
        return NULL;
    }
}

#ifndef USE_LEGACY_RB_VM_FRAME_METHOD_ENTRY
  // Taken from upstream vm_insnhelper.c at commit 5f10bd634fb6ae8f74a4ea730176233b0ca96954 (March 2022, Ruby 3.2 trunk)
  // Copyright (C) 2007 Koichi Sasada
  // to support our custom rb_profile_frames (see above)
  //
  // While older Rubies may have this function, the symbol is not exported which leads to dynamic loader issues, e.g.
  // `dyld: lazy symbol binding failed: Symbol not found: _rb_vm_frame_method_entry`.
  //
  // Modifications: None
  MJIT_STATIC const rb_callable_method_entry_t *
  rb_vm_frame_method_entry(const rb_control_frame_t *cfp)
  {
      const VALUE *ep = cfp->ep;
      rb_callable_method_entry_t *me;

      while (!VM_ENV_LOCAL_P(ep)) {
          if ((me = check_method_entry(ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE)) != NULL) return me;
          ep = VM_ENV_PREV_EP(ep);
      }

      return check_method_entry(ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE);
  }
#else
  // Taken from upstream vm_insnhelper.c at commit 556e9f726e2b80f6088982c6b43abfe68bfad591 (October 2018, ruby_2_3 branch)
  // Copyright (C) 2007 Koichi Sasada
  // to support our custom rb_profile_frames (see above)
  //
  // Quite a few macros in this function changed after Ruby 2.3. Rather than trying to fix the Ruby 3.2 version to work
  // with 2.3 constants, I decided to import the Ruby 2.3 version.
  //
  // Modifications: None
  const rb_callable_method_entry_t *
  rb_vm_frame_method_entry(const rb_control_frame_t *cfp)
  {
      VALUE *ep = cfp->ep;
      rb_callable_method_entry_t *me;

      while (!VM_EP_LEP_P(ep)) {
          if ((me = check_method_entry(ep[-1], FALSE)) != NULL) return me;
          ep = VM_EP_PREV_EP(ep);
      }

      return check_method_entry(ep[-1], TRUE);
  }
#endif // USE_LEGACY_RB_VM_FRAME_METHOD_ENTRY

#endif // RUBY_MJIT_HEADER

#else // USE_LEGACY_RB_PROFILE_FRAMES, Ruby < 2.3

// Taken from upstream vm_backtrace.c at commit bbda1a027475bf7ce5e1a9583a7b55d0be71c8fe (March 2018, ruby_2_2 branch)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
// to support our custom rb_profile_frames (see below)
// Modifications: None
inline static int
calc_lineno(const rb_iseq_t *iseq, const VALUE *pc)
{
    return rb_iseq_line_no(iseq, pc - iseq->iseq_encoded);
}

// Taken from upstream vm_backtrace.c at commit bbda1a027475bf7ce5e1a9583a7b55d0be71c8fe (March 2018, ruby_2_2 branch)
// Copyright (C) 1993-2012 Yukihiro Matsumoto
// Modifications:
// * Renamed rb_profile_frames => ddtrace_rb_profile_frames
// * Add thread argument
// * Add is_ruby_frame argument
// * Removed `if (lines)` tests -- require/assume that like `buff`, `lines` is always specified
// * Added support for getting the name from native methods by getting inspiration from `backtrace_each` in
//   `vm_backtrace.c`. Note that unlike the `rb_profile_frames` for modern Rubies, this version actually returns the
//   method name as as `VALUE` containing a Ruby string in the `buff`.
// * Skip dummy frame that shows up in main thread
// * Add `end_cfp == NULL` and `end_cfp <= cfp` safety checks. These are used in a bunch of places in
//   `vm_backtrace.c` (`backtrace_each`, `backtrace_size`, `rb_ec_partial_backtrace_object`) but are conspicuously
//   absent from `rb_profile_frames`. Oversight?
// * Distinguish between `end_cfp == NULL` (dead thread or some other error, returns 0) and `end_cfp <= cfp`
//   (alive thread which may just be executing native code and has not pushed anything on the Ruby stack, returns
//   PLACEHOLDER_STACK_IN_NATIVE_CODE). See comments on `record_placeholder_stack_in_native_code` for more details.
// * Check thread status and do not sample if thread has been killed.
//
// The `rb_profile_frames` function changed quite a bit between Ruby 2.2 and 2.3. Since the change was quite complex
// I opted not to try to extend support to Ruby 2.2 and below using the same custom function, and instead I started
// anew from the Ruby 2.2 version of the function, applying some of the same fixes that we have for the modern version.
int ddtrace_rb_profile_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines, bool* is_ruby_frame)
{
    // **IMPORTANT: THIS IS A CUSTOM RB_PROFILE_FRAMES JUST FOR RUBY 2.2 AND BELOW;
    // SEE ABOVE FOR THE FUNCTION THAT GETS USED FOR MODERN RUBIES**

    int i;
    rb_thread_t *th = thread_struct_from_object(thread);
    rb_control_frame_t *cfp = th->cfp, *end_cfp = RUBY_VM_END_CONTROL_FRAME(th);

    // `vm_backtrace.c` includes this check in several methods, and I think this happens on either dead or newly-created
    // threads, but I'm not entirely sure
    if (end_cfp == NULL) return 0;

    // Avoid sampling dead threads
    if (th->status == THREAD_KILLED) return 0;

    // Fix: Skip dummy frame that shows up in main thread.
    //
    // According to a comment in `backtrace_each` (`vm_backtrace.c`), there's two dummy frames that we should ignore
    // at the base of every thread's stack.
    // (see https://github.com/ruby/ruby/blob/4bd38e8120f2fdfdd47a34211720e048502377f1/vm_backtrace.c#L890-L914 )
    //
    // One is being pointed to by `RUBY_VM_END_CONTROL_FRAME(ec)`, and so we need to advance to the next one, and
    // reaching it will be used as a condition to break out of the loop below.
    //
    // Note that in `backtrace_each` there's two calls to `RUBY_VM_NEXT_CONTROL_FRAME`, but the loop bounds there
    // are computed in a different way, so the two calls really are equivalent to one here.
    end_cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);

    // See comment on `record_placeholder_stack_in_native_code` for a full explanation of what this means (and why we don't just return 0)
    if (end_cfp <= cfp) return PLACEHOLDER_STACK_IN_NATIVE_CODE;

    for (i=0; i<limit && cfp != end_cfp;) {
        if (cfp->iseq && cfp->pc) { /* should be NORMAL_ISEQ */
            if (start > 0) {
                start--;
                continue;
            }

            /* record frame info */
            buff[i] = cfp->iseq->self;
            lines[i] = calc_lineno(cfp->iseq, cfp->pc);
            is_ruby_frame[i] = true;
            i++;
        } else if (RUBYVM_CFUNC_FRAME_P(cfp)) {
            ID mid = cfp->me->def ? cfp->me->def->original_id : cfp->me->called_id;
            buff[i] = rb_id2str(mid);
            lines[i] = 0;
            is_ruby_frame[i] = false;
            i++;
        }
        cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }

    return i;
}

#endif // USE_LEGACY_RB_PROFILE_FRAMES
