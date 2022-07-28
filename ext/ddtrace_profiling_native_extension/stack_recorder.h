#pragma once

#include <ddprof/ffi.h>

// Note: Please DO NOT use `VALUE_STRING` anywhere else, instead use `DDPROF_FFI_CHARSLICE_C`.
// `VALUE_STRING` is only needed because older versions of gcc (4.9.2, used in our Ruby 2.2 CI test images)
// tripped when compiling `enabled_value_types` using `-std=gnu99` due to the extra cast that is included in
// `DDPROF_FFI_CHARSLICE_C` with the following error:
//
// ```
// compiling ../../../../ext/ddtrace_profiling_native_extension/stack_recorder.c
// ../../../../ext/ddtrace_profiling_native_extension/stack_recorder.c:23:1: error: initializer element is not constant
// static const ddprof_ffi_ValueType enabled_value_types[] = {CPU_TIME_VALUE, CPU_SAMPLES_VALUE, WALL_TIME_VALUE};
// ^
// ```
#define VALUE_STRING(string) {.ptr = "" string, .len = sizeof(string) - 1}

#define      CPU_TIME_VALUE {.type_ = VALUE_STRING("cpu-time"),      .unit = VALUE_STRING("nanoseconds")}
#define   CPU_SAMPLES_VALUE {.type_ = VALUE_STRING("cpu-samples"),   .unit = VALUE_STRING("count")}
#define     WALL_TIME_VALUE {.type_ = VALUE_STRING("wall-time"),     .unit = VALUE_STRING("nanoseconds")}
#define ALLOC_SAMPLES_VALUE {.type_ = VALUE_STRING("alloc-samples"), .unit = VALUE_STRING("count")}
#define   ALLOC_SPACE_VALUE {.type_ = VALUE_STRING("alloc-space"),   .unit = VALUE_STRING("bytes")}
#define    HEAP_SPACE_VALUE {.type_ = VALUE_STRING("heap-space"),    .unit = VALUE_STRING("bytes")}

static const ddprof_ffi_ValueType enabled_value_types[] = {
  #define CPU_TIME_VALUE_POS 0
  CPU_TIME_VALUE,
  #define CPU_SAMPLES_VALUE_POS 1
  CPU_SAMPLES_VALUE,
  #define WALL_TIME_VALUE_POS 2
  WALL_TIME_VALUE
};

#define ENABLED_VALUE_TYPES_COUNT (sizeof(enabled_value_types) / sizeof(ddprof_ffi_ValueType))

void record_sample(VALUE recorder_instance, ddprof_ffi_Sample sample);
void enforce_recorder_instance(VALUE object);
