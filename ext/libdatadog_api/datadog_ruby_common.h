#pragma once

// IMPORTANT: Currently this file is copy-pasted between extensions. Make sure to update all versions when doing any change!

#include <ruby.h>
#include <datadog/profiling.h>

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

// Called by ENFORCE_TYPE; should not be used directly
NORETURN(void raise_unexpected_type(VALUE value, const char *value_name, const char *type_name, const char *file, int line, const char* function_name));

// Helper to retrieve Datadog::VERSION::STRING
VALUE datadog_gem_version(void);

inline static ddog_CharSlice char_slice_from_ruby_string(VALUE string) {
  ENFORCE_TYPE(string, T_STRING);
  ddog_CharSlice char_slice = {.ptr = StringValuePtr(string), .len = RSTRING_LEN(string)};
  return char_slice;
}

__attribute__((warn_unused_result))
ddog_prof_Endpoint endpoint_from(VALUE exporter_configuration);

__attribute__((warn_unused_result))
ddog_Vec_Tag convert_tags(VALUE tags_as_array);

inline static VALUE ruby_string_from_error(const ddog_Error *error) {
  ddog_CharSlice char_slice = ddog_Error_message(error);
  return rb_str_new(char_slice.ptr, char_slice.len);
}

inline static VALUE get_error_details_and_drop(ddog_Error *error) {
  VALUE result = ruby_string_from_error(error);
  ddog_Error_drop(error);
  return result;
}
