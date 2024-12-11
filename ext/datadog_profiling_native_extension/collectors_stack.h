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
  sample_labels labels,
  VALUE optional_signal_handler_sampling_buffer
);
void record_placeholder_stack(
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels,
  ddog_CharSlice placeholder_stack
);
uint16_t sampling_buffer_check_max_frames(int max_frames);
sampling_buffer *sampling_buffer_new(uint16_t max_frames, ddog_prof_Location *locations);
void sampling_buffer_free(sampling_buffer *buffer);

VALUE signal_handler_sampling_buffer_new(uint16_t max_frames);
bool collect_stack_into_buffer(VALUE signal_handler_sampling_buffer);
VALUE pending_stack_thread_from_buffer(VALUE signal_handler_sampling_buffer);
