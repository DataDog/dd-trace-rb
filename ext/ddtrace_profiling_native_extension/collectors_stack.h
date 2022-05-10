#pragma once

typedef struct sampling_buffer sampling_buffer;

sampling_buffer *sampling_buffer_new(unsigned int max_frames);
void sampling_buffer_free(sampling_buffer *buffer);
