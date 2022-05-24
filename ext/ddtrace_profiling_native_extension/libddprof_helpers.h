#pragma once

#include <ddprof/ffi.h>

inline static ddprof_ffi_CharSlice char_slice_from_ruby_string(VALUE string) {
  Check_Type(string, T_STRING);
  ddprof_ffi_CharSlice char_slice = {.ptr = StringValuePtr(string), .len = RSTRING_LEN(string)};
  return char_slice;
}

inline static VALUE ruby_string_from_vec_u8(ddprof_ffi_Vec_u8 string) {
  return rb_str_new((char *) string.ptr, string.len);
}
