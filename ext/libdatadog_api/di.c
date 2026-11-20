#include <stdbool.h>
#include <string.h>

#include "datadog_ruby_common.h"

// rb_iseq is CRuby-specific
#ifndef TRUFFLERUBY

// Prototypes for Ruby functions declared in internal Ruby headers.
// rb_iseqw_new wraps an internal iseq pointer into a Ruby-visible
// RubyVM::InstructionSequence object.
VALUE rb_iseqw_new(const void *iseq);
// rb_iseqw_to_iseq unwraps a RubyVM::InstructionSequence object back
// to its internal iseq pointer.
const void *rb_iseqw_to_iseq(VALUE iseqw);
#ifdef HAVE_RB_IMEMO_NAME
const char *rb_imemo_name(int imemo_type);
#endif
int rb_objspace_internal_object_p(VALUE obj);
void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);

#ifdef HAVE_SHIFTED_IMEMO_MASK // Ruby 4.1+
  #define IMEMO_MASK (FL_USER0 | FL_USER1 | FL_USER2 | FL_USER3 | FL_USER4)
#else
  #define IMEMO_MASK 0x0f
#endif
#define IMEMO_TYPE_ISEQ 7

// The ID value of the string "mesg" which is used in Ruby source as
// id_mesg or idMesg, and is used to set and retrieve the exception message
// from standard library exception classes like NameError.
static ID id_mesg;

// ID for the fiber-local key that backs the method-probe re-entrancy guard.
// Storage is the same hashtable that backs Thread#[] / Thread#[]=, but accessed
// directly via rb_thread_local_aref / rb_thread_local_aset so that user-installed
// method probes on Thread#[] / Thread#[]= cannot intercept guard reads/writes.
static ID id_datadog_di_in_probe;

// ID for the ivar on each Thread object that holds that thread's snapshot
// generation token.
static ID id_datadog_di_thread_generation;

#ifdef HAVE_PRUNING_WEAKMAP
// Method IDs for the ObjectSpace::WeakMap lookups and assignments that
// store frozen threads' generation tokens.
static ID id_weakmap_aref;
static ID id_weakmap_aset;
#endif

// Process-wide source of snapshot generation tokens. Incremented only inside
// current_thread_generation, which runs with the GVL held and never releases
// it, so the counter and the accompanying ivar write need no lock.
static unsigned long long generation_counter;

// Snapshot generation tokens for Thread objects frozen before their first
// snapshot. rb_ivar_set raises FrozenError on a frozen Thread, so those
// tokens are keyed by the Thread object here instead.
//
// On releases where HAVE_PRUNING_WEAKMAP is defined the store is an
// ObjectSpace::WeakMap keyed by the Thread, which prunes an entry when
// its Thread is collected, so a Thread allocated later does not receive
// a collected thread's token. The map is kept in a static VALUE
// registered with the GC, so it outlives every entry.
//
// On every other release the store is a plain C st_table keyed by the
// Thread VALUE. The table is invisible to the GC and holds no reference
// to the Thread, so an entry outlives its thread: a Thread allocated
// later at the same address reuses the dead thread's token. No
// collection-observing API of these releases can back this store: the
// WeakMaps of Ruby 2.5 and 2.6 define a finalizer on both the key and
// the value, which a frozen Thread and an Integer token cannot take,
// the WeakMaps of Ruby 2.7 through 3.1.3 and 3.2.0 through 3.2.2
// observe collection but corrupt their internal tables during GC
// compaction (https://bugs.ruby-lang.org/issues/19529), and
// ObjectSpace.define_finalizer raises FrozenError on frozen objects,
// so the table cannot prune its entries; instead the table holds at
// most FROZEN_THREAD_GENERATION_CAP entries: an insert that would
// exceed the cap clears the table first, and a still-live frozen
// thread therefore receives a fresh token on its next snapshot, which
// keeps the table's memory bounded. Guarded by the GVL like the
// counter above.
#ifdef HAVE_PRUNING_WEAKMAP
static VALUE frozen_thread_generations;
#else
// Cap on the entries the C-table frozen-thread store can hold, bounding
// the memory the store uses in an application that churns frozen threads
// under active probes.
#define FROZEN_THREAD_GENERATION_CAP 1024
static st_table *frozen_thread_generations;
// Entries currently in the C-table store, tracked because st_table
// exposes no entry count.
static unsigned long long frozen_thread_generation_entries;
#endif

// Returns the imemo type of an imemo object, that is `imemo_type()` from CRuby's internal/imemo.h.
// The caller must have already checked the object is a T_IMEMO, otherwise the result is meaningless.
static inline int ddtrace_imemo_type(VALUE imemo) {
  #ifdef HAVE_SHIFTED_IMEMO_MASK // Ruby 4.1+
    return (RBASIC(imemo)->flags & IMEMO_MASK) >> FL_USHIFT;
  #else
    return (RBASIC(imemo)->flags >> FL_USHIFT) & IMEMO_MASK;
  #endif
}

// Returns whether the argument is an IMEMO of type ISEQ.
static bool ddtrace_imemo_iseq_p(VALUE v) {
  return rb_objspace_internal_object_p(v) && RB_TYPE_P(v, T_IMEMO) && ddtrace_imemo_type(v) == IMEMO_TYPE_ISEQ;
}

static int ddtrace_di_os_obj_of_i(void *vstart, void *vend, size_t stride, void *data)
{
  VALUE *array = (VALUE *)data;

  VALUE v = (VALUE)vstart;
  for (; v != (VALUE)vend; v += stride) {
    if (ddtrace_imemo_iseq_p(v)) {
      VALUE iseq = rb_iseqw_new((void *) v);
      rb_ary_push(*array, iseq);
    }
  }

  return 0;
}

/*
Returns all RubyVM::InstructionSequence objects existing in the current process.

This uses the same approach as ruby/debug's iseq_collector.c:
https://github.com/ruby/debug/blob/master/ext/debug/iseq_collector.c
*/
static VALUE all_iseqs(DDTRACE_UNUSED VALUE _self) {
  VALUE array = rb_ary_new();
  rb_objspace_each_objects(ddtrace_di_os_obj_of_i, &array);
  return array;
}

/*
 * call-seq:
 *   DI.exception_message(exception) -> String | Object
 *
 * Returns the exception message associated with the exception via the
 * exception's constructor.
 *
 * This method does not invoke Ruby code and as such will not call
 * the +message+ method, if one is defined on the exception object.
 *
 * Normally, the exception message is a string, however there is no
 * type enforcement done by Ruby for the messages and objects of arbitrary
 * classes can be passed to exception constructors and will, subsequently,
 * be returned by this method.
 *
 * @param exception [Exception] The exception object
 * @return [String | Object] The exception message
 */
static VALUE exception_message(DDTRACE_UNUSED VALUE _self, VALUE exception) {
  return rb_ivar_get(exception, id_mesg);
}

/*
 * call-seq:
 *   DI.in_probe? -> true | false
 *
 * Returns whether the current fiber is currently inside DI probe processing.
 * Reads the same fiber-local storage as Thread.current[:datadog_di_in_probe]
 * but bypasses Thread#[] method dispatch — a user method probe on Thread#[]
 * cannot observe or intercept this call.
 *
 * @api private
 */
static VALUE in_probe_p(DDTRACE_UNUSED VALUE _self) {
  VALUE v = rb_thread_local_aref(rb_thread_current(), id_datadog_di_in_probe);
  return RTEST(v) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   DI.enter_probe -> nil
 *
 * Marks the current fiber as inside DI probe processing. Writes to the same
 * fiber-local storage as Thread.current[:datadog_di_in_probe] = true, but
 * bypasses Thread#[]= method dispatch — a user method probe on Thread#[]=
 * cannot observe or intercept this call.
 *
 * @api private
 */
static VALUE enter_probe(DDTRACE_UNUSED VALUE _self) {
  rb_thread_local_aset(rb_thread_current(), id_datadog_di_in_probe, Qtrue);
  return Qnil;
}

/*
 * call-seq:
 *   DI.leave_probe -> nil
 *
 * Marks the current fiber as no longer inside DI probe processing. Writes to
 * the same fiber-local storage as Thread.current[:datadog_di_in_probe] = nil,
 * but bypasses Thread#[]= method dispatch — a user method probe on Thread#[]=
 * cannot observe or intercept this call.
 *
 * @api private
 */
static VALUE leave_probe(DDTRACE_UNUSED VALUE _self) {
  rb_thread_local_aset(rb_thread_current(), id_datadog_di_in_probe, Qnil);
  return Qnil;
}

/*
 * Returns the snapshot generation token of a frozen Thread, assigning
 * one from the process-wide counter on the first call for the thread.
 * Only called for a Thread whose ivar write would raise FrozenError.
 */
static VALUE frozen_thread_generation(VALUE thread) {
#ifdef HAVE_PRUNING_WEAKMAP
  VALUE generation = rb_funcall(frozen_thread_generations, id_weakmap_aref, 1, thread);
  if (!NIL_P(generation)) {
    return generation;
  }
  generation = ULL2NUM(++generation_counter);
  rb_funcall(frozen_thread_generations, id_weakmap_aset, 2, thread, generation);
  return generation;
#else
  st_data_t token;
  if (st_lookup(frozen_thread_generations, (st_data_t)thread, &token)) {
    return ULL2NUM((unsigned long long)token);
  }
  if (frozen_thread_generation_entries == FROZEN_THREAD_GENERATION_CAP) {
    st_clear(frozen_thread_generations);
    frozen_thread_generation_entries = 0;
  }
  token = (st_data_t)++generation_counter;
  st_insert(frozen_thread_generations, (st_data_t)thread, token);
  frozen_thread_generation_entries++;
  return ULL2NUM((unsigned long long)token);
#endif
}

/*
 * call-seq:
 *   DI.current_thread_generation -> Integer
 *
 * Returns the snapshot generation token for the current thread, assigning
 * one on the first call for the thread. Snapshots captured by the same
 * thread share a token, and snapshots captured by different threads carry
 * different tokens, so a consumer can tell which thread captured each
 * snapshot; on the releases that store frozen threads' tokens in the
 * C table, a Thread allocated at a collected frozen thread's address
 * receives that thread's token, and a cap-triggered clear changes a
 * still-live frozen thread's token. All fibers of a thread share that
 * thread's token. Distinct Thread objects get distinct tokens, even when
 * native thread ids are reused, with the same C-table release exception.
 * Tokens are unique only within a runtime id.
 *
 * The token is a value of the process-wide counter above, stored in an
 * ivar on the Thread object. The ivar is read via rb_attr_get, which
 * returns nil for an unset ivar and, unlike rb_ivar_get, emits no
 * verbose-mode warning on Ruby 2.6 and 2.7; it is written via rb_ivar_set.
 * A Thread frozen before its first snapshot, where writing the ivar would
 * raise FrozenError, keeps its token in process-wide storage keyed by the
 * Thread object: an ObjectSpace::WeakMap on releases whose WeakMap
 * survives GC compaction, and a C table on the remaining releases.
 * Both accesses bypass
 * Thread#thread_variable_get and Thread#thread_variable_set method dispatch,
 * so a user-installed method probe on those methods cannot fire during DI
 * snapshot building.
 *
 * @return [Integer] the generation token of the current thread
 * @api private
 */
static VALUE current_thread_generation(DDTRACE_UNUSED VALUE _self) {
  VALUE thread = rb_thread_current();
  VALUE generation = rb_attr_get(thread, id_datadog_di_thread_generation);
  if (NIL_P(generation)) {
    if (OBJ_FROZEN(thread)) {
      return frozen_thread_generation(thread);
    }
    generation = ULL2NUM(++generation_counter);
    rb_ivar_set(thread, id_datadog_di_thread_generation, generation);
  }
  return generation;
}

/*
 * call-seq:
 *   DI.hash?(obj) -> true | false
 *
 * Returns whether the given object is a Hash via a direct type check
 * (RB_TYPE_P), bypassing Kernel#is_a? method dispatch. Used in the method
 * probe wrapper (the Ruby < 3 argument-serialization split) to test whether
 * the trailing argument is a hash without giving a user-installed method
 * probe on Kernel#is_a? a chance to recurse. Matches Hash and its
 * subclasses, like is_a?(Hash), since their instances are still T_HASH.
 *
 * @api private
 */
static VALUE is_hash(DDTRACE_UNUSED VALUE _self, VALUE obj) {
  return RB_TYPE_P(obj, T_HASH) ? Qtrue : Qfalse;
}

// rb_iseq_type was added in Ruby 3.1 (commit 89a02d89 by Koichi Sasada,
// 2021-12-19). It returns the iseq type as a Symbol. On Ruby < 3.1 this
// function does not exist, so have_func('rb_iseq_type') in extconf.rb
// gates compilation. When unavailable, backfill_registry falls back to
// the first_lineno == 0 heuristic.
#ifdef HAVE_RB_ISEQ_TYPE
VALUE rb_iseq_type(const void *iseq);

/*
 * call-seq:
 *   DI.iseq_type(iseq) -> Symbol
 *
 * Returns the type of an InstructionSequence as a symbol by calling
 * the internal rb_iseq_type() function (available since Ruby 3.1).
 *
 * This method is only defined when rb_iseq_type is detected at compile
 * time via have_func in extconf.rb. On Ruby < 3.1 it is not available
 * and callers must use an alternative (e.g. first_lineno heuristic).
 *
 * Possible return values: :top, :method, :block, :class, :rescue,
 * :ensure, :eval, :main, :plain.
 *
 * :top and :main represent whole-file iseqs (from require/load and the
 * entry point script respectively). Other types represent sub-file
 * constructs (method definitions, class bodies, blocks, etc.).
 *
 * Used by CodeTracker#backfill_registry to distinguish whole-file iseqs
 * from per-method/block/class iseqs when populating the registry from
 * the object space.
 *
 * @param iseq [RubyVM::InstructionSequence] The instruction sequence
 * @return [Symbol] The iseq type
 */
static VALUE iseq_type(DDTRACE_UNUSED VALUE _self, VALUE iseq_val) {
  const void *iseq = rb_iseqw_to_iseq(iseq_val);
  if (!iseq) return Qnil;
  return rb_iseq_type(iseq);
}
#endif

/*
 * call-seq:
 *   DI::Testing._native_frozen_thread_generation_store -> Symbol
 *
 * Returns the store this extension uses for frozen-thread generation
 * tokens, as selected at compile time: :weakmap (ObjectSpace::WeakMap) or
 * :table (C table).
 *
 * @return [Symbol] the store used for frozen-thread generation tokens, `:weakmap` or `:table`
 * @api private
 */
static VALUE _native_frozen_thread_generation_store(DDTRACE_UNUSED VALUE _self) {
#ifdef HAVE_PRUNING_WEAKMAP
  return ID2SYM(rb_intern("weakmap"));
#else
  return ID2SYM(rb_intern("table"));
#endif
}

static VALUE _native_imemo_mask(DDTRACE_UNUSED VALUE _self) {
  return INT2NUM(IMEMO_MASK);
}

void di_init(VALUE datadog_module) {
  #ifdef HAVE_RB_IMEMO_NAME
    const char *iseq_name = rb_imemo_name(IMEMO_TYPE_ISEQ);
    if (strcmp(iseq_name, "iseq") != 0) {
      rb_raise(rb_eRuntimeError,
        "IMEMO_TYPE_ISEQ self-test failed: rb_imemo_name(%d) returned '%s' instead of 'iseq'",
        IMEMO_TYPE_ISEQ, iseq_name);
    }
  #endif

  id_mesg = rb_intern("mesg");
  id_datadog_di_in_probe = rb_intern("datadog_di_in_probe");
  id_datadog_di_thread_generation = rb_intern("@datadog_di_thread_generation");
#ifdef HAVE_PRUNING_WEAKMAP
  id_weakmap_aref = rb_intern("[]");
  id_weakmap_aset = rb_intern("[]=");
  VALUE object_space = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
  VALUE weakmap_class = rb_const_get(object_space, rb_intern("WeakMap"));
  frozen_thread_generations = rb_funcall(weakmap_class, rb_intern("new"), 0);
  rb_gc_register_mark_object(frozen_thread_generations);
#else
  frozen_thread_generations = st_init_numtable();
#endif

  VALUE di_module = rb_define_module_under(datadog_module, "DI");
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
  rb_define_singleton_method(di_module, "exception_message", exception_message, 1);
  rb_define_singleton_method(di_module, "in_probe?", in_probe_p, 0);
  rb_define_singleton_method(di_module, "enter_probe", enter_probe, 0);
  rb_define_singleton_method(di_module, "leave_probe", leave_probe, 0);
  rb_define_singleton_method(di_module, "hash?", is_hash, 1);
  rb_define_singleton_method(di_module, "current_thread_generation", current_thread_generation, 0);
  #ifdef HAVE_RB_ISEQ_TYPE
    rb_define_singleton_method(di_module, "iseq_type", iseq_type, 1);
  #endif

  VALUE testing_module = rb_define_module_under(di_module, "Testing");
  rb_define_singleton_method(testing_module, "_native_imemo_mask", _native_imemo_mask, 0);
  rb_define_singleton_method(
    testing_module, "_native_frozen_thread_generation_store", _native_frozen_thread_generation_store, 0);
}

#endif // TRUFFLERUBY
