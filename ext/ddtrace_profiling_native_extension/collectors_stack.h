#pragma once

#include <ddprof/ffi.h>

typedef struct sampling_buffer sampling_buffer;

void sample_thread(VALUE thread, sampling_buffer* buffer, VALUE recorder_instance, ddprof_ffi_Slice_i64 metric_values, ddprof_ffi_Slice_label labels);
sampling_buffer *sampling_buffer_new(unsigned int max_frames);
void sampling_buffer_free(sampling_buffer *buffer);
