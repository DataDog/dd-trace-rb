#pragma once

#include <datadog/profiling.h>

typedef struct sampling_buffer sampling_buffer;

void sample_thread(VALUE thread, sampling_buffer* buffer, VALUE recorder_instance, ddog_Slice_i64 metric_values, ddog_Slice_label labels);
sampling_buffer *sampling_buffer_new(unsigned int max_frames);
void sampling_buffer_free(sampling_buffer *buffer);
