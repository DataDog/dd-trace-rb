#pragma once

#include <datadog/profiling.h>
#include "ruby_helpers.h"

inline static ddog_CharSlice char_slice_from_ruby_string(VALUE string) {
  ENFORCE_TYPE(string, T_STRING);
  ddog_CharSlice char_slice = {.ptr = StringValuePtr(string), .len = RSTRING_LEN(string)};
  return char_slice;
}

inline static VALUE ruby_string_from_vec_u8(ddog_Vec_U8 string) {
  return rb_str_new((char *) string.ptr, string.len);
}

inline static VALUE ruby_string_from_prof_vec_u8(ddog_prof_Vec_U8 string) {
  return rb_str_new((char *) string.ptr, string.len);
}
