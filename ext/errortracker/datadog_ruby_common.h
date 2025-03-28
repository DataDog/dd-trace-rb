#pragma once

// IMPORTANT: Currently this file is copy-pasted between extensions. Make sure to update all versions when doing any change!

#include <ruby.h>

// Used to mark symbols to be exported to the outside of the extension.
// Consider very carefully before tagging a function with this.
#define DDTRACE_EXPORT __attribute__ ((visibility ("default")))

// Used to mark function arguments that are deliberately left unused
#ifdef __GNUC__
  #define DDTRACE_UNUSED  __attribute__((unused))
#else
  #define DDTRACE_UNUSED
#endif

#define ADD_QUOTES_HELPER(x) #x
#define ADD_QUOTES(x) ADD_QUOTES_HELPER(x)

// Ruby has a Check_Type(value, type) that is roughly equivalent to this BUT Ruby's version is rather cryptic when it fails
// e.g. "wrong argument type nil (expected String)". This is a replacement that prints more information to help debugging.
#define ENFORCE_TYPE(value, type) \
  { if (RB_UNLIKELY(!RB_TYPE_P(value, type))) raise_unexpected_type(value, ADD_QUOTES(value), ADD_QUOTES(type), __FILE__, __LINE__, __func__); }

#define ENFORCE_BOOLEAN(value) \
  { if (RB_UNLIKELY(value != Qtrue && value != Qfalse)) raise_unexpected_type(value, ADD_QUOTES(value), "true or false", __FILE__, __LINE__, __func__); }

NORETURN(void raise_unexpected_type(VALUE value, const char *value_name, const char *type_name, const char *file, int line, const char* function_name));