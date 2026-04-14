#pragma once

#include <stdbool.h>
#include <stdarg.h>
#include "datadog_ruby_common.h"

// Initialize internal data needed by some ruby helpers. Should be called during start, before any actual
// usage of ruby helpers.
void ruby_helpers_init(void);

// Processes any pending interruptions, including exceptions to be raised.
// If there's an exception to be raised, it raises it. In that case, this function does not return.
static inline VALUE process_pending_interruptions(DDTRACE_UNUSED VALUE _) {
  rb_thread_check_ints();
  return Qnil;
}

// Calls process_pending_interruptions BUT "rescues" any exceptions to be raised, returning them instead as
// a non-zero `pending_exception`.
//
// Thus, if there's a non-zero `pending_exception`, the caller MUST call `rb_jump_tag(pending_exception)` after any
// needed clean-ups.
//
// Usage example:
//
// ```c
// foo = ruby_xcalloc(...);
// pending_exception = check_if_pending_exception();
// if (pending_exception) {
//   ruby_xfree(foo);
//   rb_jump_tag(pending_exception); // Re-raises exception
// }
// ```
__attribute__((warn_unused_result))
static inline int check_if_pending_exception(void) {
  int pending_exception;
  rb_protect(process_pending_interruptions, Qnil, &pending_exception);
  return pending_exception;
}

#define VALUE_COUNT(array) (sizeof(array) / sizeof(VALUE))

// rb_gc_mark_movable and rb_gc_location were added in Ruby 2.7 for GC compaction support.
// On older Rubies we polyfill: mark_movable falls back to rb_gc_mark (pins objects),
// and rb_gc_location is a no-op since objects never move.
#ifdef NO_T_MOVED
  #define rb_gc_mark_movable(obj) rb_gc_mark(obj)
  #define rb_gc_location(obj) (obj)
#endif

// Declarative marking (RUBY_TYPED_DECL_MARKING, RUBY_REFERENCES, etc.) was added in Ruby 3.3.
// On older Rubies we polyfill the macros so the reference lists can be defined unconditionally.
// The RUBY_TYPED_DECL_MARKING flag becomes 0 so it's a no-op when OR'd into flags.
// NOTE: The .dmark field still needs to select the correct value (refs list vs callback) via ifdef,
// since passing a refs list as a function pointer on older Rubies would crash.
#ifdef NO_DECL_MARKING
  #define RUBY_TYPED_DECL_MARKING  0
  #define RUBY_REFERENCES(name)    static const size_t name[]
  #define RUBY_REF_EDGE(type, member) offsetof(type, member)
  #define RUBY_REF_END             /* empty -- on old Rubies the helpers use the array size instead */
#endif

// Ruby 2.7-3.2: has .dcompact in the struct but no declarative marking, so we need manual dcompact callbacks.
// Ruby < 2.7: no .dcompact field at all. Ruby 3.3+: declarative marking handles compaction automatically.
#if defined(NO_DECL_MARKING) && !defined(NO_T_MOVED)
  #define NEEDS_DCOMPACT 1
#endif

// Generic mark/compact helpers that iterate a RUBY_REFERENCES list.
// On Ruby < 3.3, these are used by the manual dmark/dcompact callbacks. The field list is defined once
// in a RUBY_REFERENCES array and reused here, by dcompact, and (on 3.3+) by declarative marking.
// Pass sizeof(refs_array) so the count is computed at compile time with no sentinel needed.
static inline void ddtrace_gc_mark_refs(const size_t *refs, size_t refs_sizeof, void *data) {
  for (size_t i = 0; i < refs_sizeof / sizeof(size_t); i++) {
    rb_gc_mark_movable(*(VALUE *)((char *)data + refs[i]));
  }
}

static inline void ddtrace_gc_compact_refs(const size_t *refs, size_t refs_sizeof, void *data) {
  for (size_t i = 0; i < refs_sizeof / sizeof(size_t); i++) {
    VALUE *field = (VALUE *)((char *)data + refs[i]);
    *field = rb_gc_location(*field);
  }
}

// rb_hash_bulk_insert was added in Ruby 2.6 to insert key-value pairs from a flat array
// into a hash in one call. On older Rubies we polyfill it with a simple loop.
#ifdef NO_RB_HASH_BULK_INSERT
static inline void rb_hash_bulk_insert(long argc, const VALUE *argv, VALUE hash) {
  for (long i = 0; i < argc; i += 2) rb_hash_aset(hash, argv[i], argv[i + 1]);
}
#endif

// Raises a SysErr exception with the formatted string as its message.
// See `raise_error` for details about telemetry messages.
#define raise_syserr(syserr_errno, fmt, ...) \
  private_raise_syserr(syserr_errno, "" fmt, ##__VA_ARGS__)

#define grab_gvl_and_raise(exception_class, fmt, ...) \
  private_grab_gvl_and_raise(exception_class, 0, "" fmt, ##__VA_ARGS__)

NORETURN(
  void private_raise_syserr(int syserr_errno, const char *fmt, ...)
  __attribute__ ((format (printf, 2, 3)));
);

NORETURN(
  void private_grab_gvl_and_raise(VALUE exception_class, int syserr_errno, const char *format_string, ...)
  __attribute__ ((format (printf, 3, 4)));
);



#define ENFORCE_SUCCESS_GVL(expression) ENFORCE_SUCCESS_HELPER(expression, true)
#define ENFORCE_SUCCESS_NO_GVL(expression) ENFORCE_SUCCESS_HELPER(expression, false)

#define ENFORCE_SUCCESS_HELPER(expression, have_gvl) \
  { int result_syserr_errno = expression; if (RB_UNLIKELY(result_syserr_errno)) private_raise_enforce_syserr(result_syserr_errno, have_gvl, ADD_QUOTES(expression), __FILE__, __LINE__, __func__); }

#define RUBY_NUM_OR_NIL(val, condition, conv) ((val condition) ? conv(val) : Qnil)
#define RUBY_AVG_OR_NIL(total, count) ((count == 0) ? Qnil : DBL2NUM(((double) total) / count))

// Called by ENFORCE_SUCCESS_HELPER; should not be used directly
NORETURN(void private_raise_enforce_syserr(
  int syserr_errno,
  bool have_gvl,
  const char *expression,
  const char *file,
  int line,
  const char *function_name
));

// Native wrapper to get an object ref from an id. Returns true on success and
// writes the ref to the value pointer parameter if !NULL. False if id doesn't
// reference a valid object (in which case value is not changed).
//
// Note: GVL can be released and other threads may get to run before this method returns
bool ruby_ref_from_id(VALUE obj_id, VALUE *value);

// Native wrapper to get the approximate/estimated current size of the passed
// object.
size_t ruby_obj_memsize_of(VALUE obj);

// Safely inspect any ruby object. If the object responds to 'inspect',
// return a string with the result of that call. Elsif the object responds to
// 'to_s', return a string with the result of that call. Otherwise, return Qnil.
VALUE ruby_safe_inspect(VALUE obj);

// You probably want ruby_safe_inspect instead; this is a lower-level dependency
// of it, that's being exposed here just to facilitate testing.
const char* safe_object_info(VALUE obj);
