#pragma once

#include <datadog/profiling.h>
#include "ruby_helpers.h"

// Extracts the error from a ddog_prof_Status, drops the status to prevent a memory leak, and raises
// a Ruby RuntimeError. Must only be called when s_ptr->err != NULL.
// Usage: if (s.err != NULL) raise_status_error("Failed to do X", &s);
#define raise_status_error(prefix, s_ptr) \
  do { \
    VALUE _raise_status_msg = rb_str_new_cstr((s_ptr)->err); \
    ddog_prof_Status_drop(s_ptr); \
    raise_error(rb_eRuntimeError, prefix ": %"PRIsVALUE, _raise_status_msg); \
  } while(0)

static inline VALUE ruby_string_from_vec_u8(ddog_Vec_U8 string) {
  return rb_str_new((char *) string.ptr, string.len);
}

// Used for pretty printing this Ruby enum. Returns "T_UNKNOWN_OR_MISSING_RUBY_VALUE_TYPE_ENTRY" for unknown elements.
// In practice, there's a few types that the profiler will probably never encounter, but I've added all entries of
// ruby_value_type that Ruby uses so that we can also use this for debugging.
const char *ruby_value_type_to_string(enum ruby_value_type type);
ddog_CharSlice ruby_value_type_to_char_slice(enum ruby_value_type type);

ddog_prof_ManagedStringId intern_or_raise(ddog_prof_ManagedStringStorage string_storage, ddog_CharSlice string);

void intern_all_or_raise(
  ddog_prof_ManagedStringStorage string_storage,
  ddog_prof_Slice_CharSlice strings,
  ddog_prof_ManagedStringId *output_ids,
  uintptr_t output_ids_size
);
