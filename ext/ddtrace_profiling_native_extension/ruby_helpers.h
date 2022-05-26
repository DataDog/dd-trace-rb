#pragma once

#include <ruby.h>

// Processes any pending interruptions, including exceptions to be raised.
// If there's an exception to be raised, it raises it.
static inline VALUE process_pending_interruptions(VALUE _unused) {
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
static inline int check_if_pending_exception() {
  int pending_exception;
  rb_protect(process_pending_interruptions, Qnil, &pending_exception);
  return pending_exception;
}
