#pragma once

#include <ddprof/ffi.h>

inline static ddprof_ffi_CharSlice char_slice_from_ruby_string(VALUE string) {
  Check_Type(string, T_STRING);
  ddprof_ffi_CharSlice char_slice = {.ptr = StringValuePtr(string), .len = RSTRING_LEN(string)};
  return char_slice;
}
