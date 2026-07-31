#pragma once

#include <datadog/profiling.h>

#include "private_vm_api_access.h"
#include "stack_recorder.h"

#define MAX_FRAMES_LIMIT            3000
#define MAX_FRAMES_LIMIT_AS_STRING "3000"

// Per thread, where we store the stack sample
typedef struct {
  uint16_t max_frames;
  frame_info *stack_buffer;
  bool pending_sample;
  bool is_marking; // Used to avoid recording a sample when marking
  int pending_sample_result;
} sampling_buffer;

// 1 per ThreadContext so effectively global.
// Used to pass the stack of ddog_prof_Location's to libdatadog.
typedef struct {
  ddog_prof_Location *ptr;
  uint16_t len;
  // This buffer is used when composing qualified method names (e.g. with module/class name).
  // Because we get only the individual parts from Ruby, we need scratch space to lay out the contiguous frame name for libdatadog to use.
  // The same big buffer is used to try to contain all of the qualified method names needed for a given stack, one after another.
  // Whenever we run out of space, we stop composing the full qualified names and fall back
  // to only showing the method names for that stack.
  // TODO: In the future we'd hopefully intern the qualified names into libdatadog and stop needing this buffer.
  char *qualified_name_buf;
  size_t qualified_name_buf_size;
} sample_locations;

void sample_thread(
  VALUE thread,
  sampling_buffer* buffer,
  sample_locations locations,
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels,
  bool native_filenames_enabled,
  st_table *native_filenames_cache,
  bool show_classes
);
void record_placeholder_stack(
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels,
  ddog_CharSlice placeholder_stack
);
bool prepare_sample_thread(VALUE thread, sampling_buffer *buffer);

void sample_locations_initialize(sample_locations *locations, uint16_t max_frames, bool show_classes);
void sample_locations_free(sample_locations *locations);

uint16_t sampling_buffer_check_max_frames(int max_frames);
void sampling_buffer_initialize(sampling_buffer *buffer, uint16_t max_frames);
void sampling_buffer_free(sampling_buffer *buffer);
void sampling_buffer_mark(sampling_buffer *buffer);
static inline bool sampling_buffer_needs_marking(sampling_buffer *buffer) {
  return buffer->pending_sample && buffer->pending_sample_result > 0;
}
