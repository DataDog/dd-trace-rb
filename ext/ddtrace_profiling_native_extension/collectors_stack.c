#include <ruby.h>
#include <ruby/debug.h>
#include "libddprof_helpers.h"
#include "private_vm_api_access.h"
#include "stack_recorder.h"

// Gathers stack traces from running threads, storing them in a StackRecorder instance
// This file implements the native bits of the Datadog::Profiling::Collectors::Stack class

static VALUE missing_string = Qnil;

static VALUE _native_sample(VALUE self, VALUE thread, VALUE recorder_instance, VALUE metric_values_hash, VALUE labels_array);
void sample(VALUE thread, VALUE recorder_instance, ddprof_ffi_Slice_i64 metric_values, ddprof_ffi_Slice_label labels);

void collectors_stack_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_stack_class = rb_define_class_under(collectors_module, "Stack", rb_cObject);

  rb_define_singleton_method(collectors_stack_class, "_native_sample", _native_sample, 4);

  missing_string = rb_str_new2("");
  rb_global_variable(&missing_string);
}

// This method exists only to enable testing Collectors::Stack behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(VALUE self, VALUE thread, VALUE recorder_instance, VALUE metric_values_hash, VALUE labels_array) {
  Check_Type(metric_values_hash, T_HASH);
  Check_Type(labels_array, T_ARRAY);

  if (rb_hash_size_num(metric_values_hash) != ENABLED_VALUE_TYPES_COUNT) {
    rb_raise(
      rb_eArgError,
      "Mismatched values for metrics; expected %lu values and got %lu instead",
      ENABLED_VALUE_TYPES_COUNT,
      rb_hash_size_num(metric_values_hash)
    );
  }

  int64_t metric_values[ENABLED_VALUE_TYPES_COUNT];
  for (int i = 0; i < ENABLED_VALUE_TYPES_COUNT; i++) {
    VALUE metric_value = rb_hash_fetch(metric_values_hash, rb_str_new_cstr(enabled_value_types[i].type_.ptr));
    metric_values[i] = NUM2LONG(metric_value);
  }

  int labels_count = RARRAY_LEN(labels_array);
  ddprof_ffi_Label labels[labels_count];

  for (int i = 0; i < labels_count; i++) {
    VALUE key_str_pair = rb_ary_entry(labels_array, i);

    labels[i] = (ddprof_ffi_Label) {
      .key = char_slice_from_ruby_string(rb_ary_entry(key_str_pair, 0)),
      .str = char_slice_from_ruby_string(rb_ary_entry(key_str_pair, 1))
    };
  }

  sample(
    thread,
    recorder_instance,
    (ddprof_ffi_Slice_i64) {.ptr = metric_values, .len = ENABLED_VALUE_TYPES_COUNT},
    (ddprof_ffi_Slice_label) {.ptr = labels, .len = labels_count}
  );

  return Qtrue;
}

void sample(VALUE thread, VALUE recorder_instance, ddprof_ffi_Slice_i64 metric_values, ddprof_ffi_Slice_label labels) {
  const int max_frames = 400; // FIXME: Should be configurable
  VALUE stack_buffer[max_frames];
  int lines_buffer[max_frames];

  int captured_frames = ddtrace_rb_profile_frames(thread, 0 /* stack starting depth */, max_frames, stack_buffer, lines_buffer);

  ddprof_ffi_Location locations[captured_frames];
  ddprof_ffi_Line lines[captured_frames];

  for (int i = 0; i < captured_frames; i++) {
    VALUE name = rb_profile_frame_base_label(stack_buffer[i]);
    VALUE filename = rb_profile_frame_path(stack_buffer[i]);

    name = NIL_P(name) ? missing_string : name;
    filename = NIL_P(filename) ? missing_string : filename;

    lines[i] = (ddprof_ffi_Line) {
      .function = (ddprof_ffi_Function) {
        .name = char_slice_from_ruby_string(name),
        .filename = char_slice_from_ruby_string(filename)
      },
      .line = lines_buffer[i],
    };

    locations[i] = (ddprof_ffi_Location) {.lines = (ddprof_ffi_Slice_line) {.ptr = &lines[i], .len = 1}};
  }

  record_sample(
    recorder_instance,
    (ddprof_ffi_Sample) {
      .locations = (ddprof_ffi_Slice_location) {.ptr = locations, .len = captured_frames},
      .values = metric_values,
      .labels = labels,
    }
  );
}
