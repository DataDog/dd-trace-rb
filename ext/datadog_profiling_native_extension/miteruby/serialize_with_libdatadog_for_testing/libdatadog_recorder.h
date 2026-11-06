#pragma once

#include <datadog/profiling.h>
#include <ruby.h>

#include "../sample_values.h"

void miteruby_libdatadog_recorder_init(VALUE profiling_module);

// Callers hold the GVL; reentrant access during serialization is rejected.
VALUE miteruby_libdatadog_recorder_enforce_available(VALUE recorder);
void miteruby_libdatadog_recorder_record_sample(
  VALUE recorder, ddog_prof_Slice_Location locations, miteruby_sample_values values,
  ddog_prof_Slice_Label labels, int64_t end_timestamp_ns
);
