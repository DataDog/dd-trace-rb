#include <ruby.h>
#include <ruby/debug.h>
#include "libddprof_helpers.h"
#include "private_vm_api_access.h"
#include "stack_recorder.h"

// Gathers stack traces from running threads, storing them in a StackRecorder instance
// This file implements the native bits of the Datadog::Profiling::Collectors::Stack class

static VALUE missing_string = Qnil;

// Used as scratch space during sampling
typedef struct sampling_buffer {
  int max_frames;
  VALUE *stack_buffer;
  int *lines_buffer;
  bool *is_ruby_frame;
  ddprof_ffi_Location *locations;
  ddprof_ffi_Line *lines;
} sampling_buffer;

static VALUE _native_sample(VALUE self, VALUE thread, VALUE recorder_instance, VALUE metric_values_hash, VALUE labels_array, VALUE max_frames);
void sample(VALUE thread, sampling_buffer* buffer, VALUE recorder_instance, ddprof_ffi_Slice_i64 metric_values, ddprof_ffi_Slice_label labels);
sampling_buffer *sampling_buffer_new(int max_frames);
void sampling_buffer_free(sampling_buffer *buffer);

void collectors_stack_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_stack_class = rb_define_class_under(collectors_module, "Stack", rb_cObject);

  rb_define_singleton_method(collectors_stack_class, "_native_sample", _native_sample, 5);

  missing_string = rb_str_new2("");
  rb_global_variable(&missing_string);
}

// This method exists only to enable testing Collectors::Stack behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(VALUE self, VALUE thread, VALUE recorder_instance, VALUE metric_values_hash, VALUE labels_array, VALUE max_frames) {
  Check_Type(metric_values_hash, T_HASH);
  Check_Type(labels_array, T_ARRAY);

  if (RHASH_SIZE(metric_values_hash) != ENABLED_VALUE_TYPES_COUNT) {
    rb_raise(
      rb_eArgError,
      "Mismatched values for metrics; expected %lu values and got %lu instead",
      ENABLED_VALUE_TYPES_COUNT,
      RHASH_SIZE(metric_values_hash)
    );
  }

  int64_t metric_values[ENABLED_VALUE_TYPES_COUNT];
  for (unsigned int i = 0; i < ENABLED_VALUE_TYPES_COUNT; i++) {
    VALUE metric_value = rb_hash_fetch(metric_values_hash, rb_str_new_cstr(enabled_value_types[i].type_.ptr));
    metric_values[i] = NUM2LONG(metric_value);
  }

  long labels_count = RARRAY_LEN(labels_array);
  ddprof_ffi_Label labels[labels_count];

  for (int i = 0; i < labels_count; i++) {
    VALUE key_str_pair = rb_ary_entry(labels_array, i);

    labels[i] = (ddprof_ffi_Label) {
      .key = char_slice_from_ruby_string(rb_ary_entry(key_str_pair, 0)),
      .str = char_slice_from_ruby_string(rb_ary_entry(key_str_pair, 1))
    };
  }

  sampling_buffer *buffer = sampling_buffer_new(NUM2INT(max_frames));

  sample(
    thread,
    buffer,
    recorder_instance,
    (ddprof_ffi_Slice_i64) {.ptr = metric_values, .len = ENABLED_VALUE_TYPES_COUNT},
    (ddprof_ffi_Slice_label) {.ptr = labels, .len = labels_count}
  );

  sampling_buffer_free(buffer);

  return Qtrue;
}

void sample(VALUE thread, sampling_buffer* buffer, VALUE recorder_instance, ddprof_ffi_Slice_i64 metric_values, ddprof_ffi_Slice_label labels) {
  int captured_frames = ddtrace_rb_profile_frames(
    thread,
    0 /* stack starting depth */,
    buffer->max_frames,
    buffer->stack_buffer,
    buffer->lines_buffer,
    buffer->is_ruby_frame
  );

  // Ruby does not give us path and line number for methods implemented using native code.
  // The convention in Kernel#caller_locations is to instead use the path and line number of the first Ruby frame
  // on the stack that is below (e.g. directly or indirectly has called) the native method.
  // Thus, we keep that frame here to able to replicate that behavior.
  // (This is why we also iterate the sampling buffers backwards below -- so that it's easier to keep the last_ruby_frame)
  VALUE last_ruby_frame = Qnil;
  int last_ruby_line = 0;

  for (int i = captured_frames - 1; i >= 0; i--) {
    VALUE name, filename;
    int line;

    if (buffer->is_ruby_frame[i]) {
      last_ruby_frame = buffer->stack_buffer[i];
      last_ruby_line = buffer->lines_buffer[i];

      name = rb_profile_frame_base_label(buffer->stack_buffer[i]);
      filename = rb_profile_frame_path(buffer->stack_buffer[i]);
      line = buffer->lines_buffer[i];
    } else {
      name = ddtrace_rb_profile_frame_method_name(buffer->stack_buffer[i]);
      filename = NIL_P(last_ruby_frame) ? Qnil : rb_profile_frame_path(last_ruby_frame);
      line = last_ruby_line;
    }

    name = NIL_P(name) ? missing_string : name;
    filename = NIL_P(filename) ? missing_string : filename;

    buffer->lines[i] = (ddprof_ffi_Line) {
      .function = (ddprof_ffi_Function) {
        .name = char_slice_from_ruby_string(name),
        .filename = char_slice_from_ruby_string(filename)
      },
      .line = line,
    };

    buffer->locations[i] = (ddprof_ffi_Location) {.lines = (ddprof_ffi_Slice_line) {.ptr = &buffer->lines[i], .len = 1}};
  }

  record_sample(
    recorder_instance,
    (ddprof_ffi_Sample) {
      .locations = (ddprof_ffi_Slice_location) {.ptr = buffer->locations, .len = captured_frames},
      .values = metric_values,
      .labels = labels,
    }
  );
}

sampling_buffer *sampling_buffer_new(int max_frames) {
  sampling_buffer* buffer = xcalloc(1, sizeof(sampling_buffer));
  if (buffer == NULL) rb_raise(rb_eNoMemError, "Failed to allocate memory for sampling buffer");

  buffer->max_frames = max_frames;

  buffer->stack_buffer  = xcalloc(max_frames, sizeof(VALUE));
  buffer->lines_buffer  = xcalloc(max_frames, sizeof(int));
  buffer->is_ruby_frame = xcalloc(max_frames, sizeof(bool));
  buffer->locations     = xcalloc(max_frames, sizeof(ddprof_ffi_Location));
  buffer->lines         = xcalloc(max_frames, sizeof(ddprof_ffi_Line));

  if (
    buffer->stack_buffer  == NULL ||
    buffer->lines_buffer  == NULL ||
    buffer->is_ruby_frame == NULL ||
    buffer->locations     == NULL ||
    buffer->lines         == NULL
  ) {
    sampling_buffer_free(buffer);
    rb_raise(rb_eNoMemError, "Failed to allocate memory for components of sampling buffer");
  }

  return buffer;
}

void sampling_buffer_free(sampling_buffer *buffer) {
  // The only case where any of the underlying arrays are NULL is when initial allocation failed; otherwise they
  // can be assumed to be not-null.
  // Having these if tests here enables us to use this function also in sampling_buffer_new; otherwise we could do
  // without them.
  if (buffer->stack_buffer  != NULL) xfree(buffer->stack_buffer);
  if (buffer->lines_buffer  != NULL) xfree(buffer->lines_buffer);
  if (buffer->is_ruby_frame != NULL) xfree(buffer->is_ruby_frame);
  if (buffer->locations     != NULL) xfree(buffer->locations);
  if (buffer->lines         != NULL) xfree(buffer->lines);

  xfree(buffer);
}
