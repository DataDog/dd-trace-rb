#pragma once

#include <datadog/profiling.h>

typedef struct sample_values {
  int64_t cpu_time_ns;
  int64_t wall_time_ns;
  uint32_t cpu_samples;
  uint32_t alloc_samples;
} sample_values;

void record_sample(VALUE recorder_instance, ddog_prof_Slice_Location locations, sample_values values, ddog_prof_Slice_Label labels);
void record_endpoint(VALUE recorder_instance, uint64_t local_root_span_id, ddog_CharSlice endpoint);
VALUE enforce_recorder_instance(VALUE object);
