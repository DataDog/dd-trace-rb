#pragma once

#include <datadog/profiling.h>

#include "private_vm_api_access.h"
#include "stack_recorder.h"

#define MAX_FRAMES_LIMIT            3000
#define MAX_FRAMES_LIMIT_AS_STRING "3000"

// An estimation of how much bytes we need on average for qualified method names
#define QUALIFIED_NAME_AVG_SIZE 64

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
  // We need a pre-allocated buffer to compute qualified methods names (e.g. Foo::Bar#baz),
  // to avoid expensive runtime allocations for this.
  // We need some space for each frame, because we send the whole stacktrace at once to libdatadog (currently).
  // When we run out of space we stop qualifying method names and just return the raw method name.
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
  bool include_module_name
);
void record_placeholder_stack(
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels,
  ddog_CharSlice placeholder_stack
);
bool prepare_sample_thread(VALUE thread, sampling_buffer *buffer);

void sample_locations_initialize(sample_locations *locations, uint16_t max_frames, bool include_module_name);
void sample_locations_free(sample_locations *locations);

uint16_t sampling_buffer_check_max_frames(int max_frames);
void sampling_buffer_initialize(sampling_buffer *buffer, uint16_t max_frames);
void sampling_buffer_free(sampling_buffer *buffer);
void sampling_buffer_mark(sampling_buffer *buffer);
static inline bool sampling_buffer_needs_marking(sampling_buffer *buffer) {
  return buffer->pending_sample && buffer->pending_sample_result > 0;
}
