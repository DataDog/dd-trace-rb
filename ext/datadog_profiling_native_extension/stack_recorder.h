#pragma once

#include <datadog/profiling.h>
#include <ruby.h>

typedef struct {
  // In: The object being allocated, and its class. (Its weight is the `alloc_samples` in `sample_values` below.)
  VALUE new_object;
  ddog_CharSlice alloc_class;
  // Out: Set by `record_sample` to whether a `recorder_commit_heap_recordings_may_lose_gvl` callback is needed
  bool out_needs_commit;
} heap_sample_values;

typedef struct {
  int64_t cpu_time_ns;
  int64_t wall_time_ns;
  uint32_t cpu_or_wall_samples;
  uint32_t alloc_samples;
  uint32_t alloc_samples_unscaled;
  int64_t timeline_wall_time_ns;
  // When not NULL, this sample also gets recorded for heap profiling
  heap_sample_values *heap_sample;
} sample_values;

typedef struct {
  ddog_prof_Slice_Label labels;

  // This is used to allow the `Collectors::Stack` to modify the existing label, if any. This MUST be NULL or point
  // somewhere inside the labels slice above.
  ddog_prof_Label *state_label;
  bool is_gvl_waiting_state;

  int64_t end_timestamp_ns;
} sample_labels;

void record_sample(VALUE recorder_instance, ddog_prof_Slice_Location locations, sample_values values, sample_labels labels);
void record_endpoint(VALUE recorder_instance, uint64_t local_root_span_id, ddog_CharSlice endpoint);
void recorder_commit_heap_recordings_may_lose_gvl(VALUE recorder_instance);
void recorder_heap_update_may_lose_gvl(VALUE recorder_instance);
void recorder_install_on_serialize(VALUE recorder_instance, VALUE thread_context_collector_instance);
VALUE enforce_recorder_instance(VALUE object);
