#pragma once

#include <ruby.h>

// Processes any pending interruptions, including exceptions to be raised.
// If there's an exception to be raised, it raises it. In that case, this function does not return.
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
static inline int check_if_pending_exception(void) {
  int pending_exception;
  rb_protect(process_pending_interruptions, Qnil, &pending_exception);
  return pending_exception;
}

#define ADD_QUOTES_HELPER(x) #x
#define ADD_QUOTES(x) ADD_QUOTES_HELPER(x)

// Ruby has a Check_Type(value, type) that is roughly equivalent to this BUT Ruby's version is rather cryptic when it fails
// e.g. "wrong argument type nil (expected String)". This is a replacement that prints more information to help debugging.
#define ENFORCE_TYPE(value, type) \
  { if (RB_UNLIKELY(!RB_TYPE_P(value, type))) raise_unexpected_type(value, type, ADD_QUOTES(value), ADD_QUOTES(type), __FILE__, __LINE__, __func__); }

// Called by ENFORCE_TYPE; should not be used directly
void raise_unexpected_type(
  VALUE value,
  enum ruby_value_type type,
  const char *value_name,
  const char *type_name,
  const char *file,
  int line,
  const char* function_name
);
