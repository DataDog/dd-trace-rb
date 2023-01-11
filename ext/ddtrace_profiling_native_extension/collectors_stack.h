#pragma once

#include <datadog/profiling.h>

typedef struct sampling_buffer sampling_buffer;

typedef enum { SAMPLE_REGULAR, SAMPLE_IN_GC } sample_type;

void sample_thread(
  VALUE thread,
  sampling_buffer* buffer,
  VALUE recorder_instance,
  ddog_Slice_I64 metric_values,
  ddog_prof_Slice_Label labels,
  sample_type type
);
sampling_buffer *sampling_buffer_new(unsigned int max_frames);
void sampling_buffer_free(sampling_buffer *buffer);
