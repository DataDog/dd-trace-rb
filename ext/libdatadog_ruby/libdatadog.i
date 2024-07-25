%module libdatadog_ruby

%{
  #include <datadog/common.h>
  #include <datadog/profiling.h>
%}

%typemap(in) uintptr_t {
  $1 = (uintptr_t) NUM2ULONG($input);
}

%typemap(in) uint64_t {
  $1 = (uint64_t) NUM2ULONG($input);
}

%typemap(out) struct ddog_Error* {
  ddog_CharSlice char_slice = ddog_Error_message($1);
  $result = rb_str_new(char_slice.ptr, char_slice.len);
}

%include <datadog/common.h>
%include <datadog/profiling.h>
