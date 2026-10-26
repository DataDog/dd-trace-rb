#pragma once

#include <datadog/profiling.h>
#include <ruby.h>

typedef struct {
  int64_t cpu_time_ns;
  uint32_t cpu_or_wall_samples;
  int64_t wall_time_ns;
  uint32_t alloc_samples;
  uint32_t alloc_samples_unscaled;
  int64_t timeline_wall_time_ns;
} miteruby_sample_values;

void miteruby_libdatadog_recorder_init(VALUE profiling_module);

// Callers hold the GVL; access is rejected while serialization owns the profile without the GVL.
VALUE miteruby_libdatadog_recorder_enforce_available(VALUE recorder);
void miteruby_libdatadog_recorder_record_sample(
  VALUE recorder, ddog_prof_Slice_Location locations, miteruby_sample_values values,
  ddog_prof_Slice_Label labels, int64_t end_timestamp_ns
);
void miteruby_libdatadog_recorder_record_endpoint(VALUE recorder, uint64_t local_root_span_id, ddog_CharSlice endpoint);
