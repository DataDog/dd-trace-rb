#pragma once

#include <ruby.h>

#include "helpers.h"

// Processes any pending interruptions, including exceptions to be raised.
// If there's an exception to be raised, it raises it. In that case, this function does not return.
static inline VALUE process_pending_interruptions(DDTRACE_UNUSED VALUE _) {
  rb_thread_check_ints();
  return Qnil;
}

// RB_UNLIKELY is not supported on Ruby 2.2 and 2.3
#ifndef RB_UNLIKELY
  #define RB_UNLIKELY(x) x
#endif

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
NORETURN(void raise_unexpected_type(
  VALUE value,
  enum ruby_value_type type,
  const char *value_name,
  const char *type_name,
  const char *file,
  int line,
  const char* function_name
));

// This API is exported as a public symbol by the VM BUT the function header is not defined in any public header, so we
// repeat it here to be able to use in our code.
//
// Queries if the current thread is the owner of the global VM lock.
int ruby_thread_has_gvl_p(void);
