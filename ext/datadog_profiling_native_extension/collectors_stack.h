#pragma once

#include <datadog/profiling.h>

#include "stack_recorder.h"

#define MAX_FRAMES_LIMIT            10000
#define MAX_FRAMES_LIMIT_AS_STRING "10000"

typedef struct sampling_buffer sampling_buffer;

void sample_thread(
  VALUE thread,
  sampling_buffer* buffer,
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels
);
void record_placeholder_stack(
  sampling_buffer* buffer,
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels,
  ddog_CharSlice placeholder_stack
);
sampling_buffer *sampling_buffer_new(unsigned int max_frames);
void sampling_buffer_free(sampling_buffer *buffer);
