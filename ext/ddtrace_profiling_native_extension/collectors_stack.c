#include <ruby.h>
#include <ruby/debug.h>
#include "extconf.h"
#include "helpers.h"
#include "libdatadog_helpers.h"
#include "ruby_helpers.h"
#include "private_vm_api_access.h"
#include "stack_recorder.h"
#include "collectors_stack.h"

// Gathers stack traces from running threads, storing them in a StackRecorder instance
// This file implements the native bits of the Datadog::Profiling::Collectors::Stack class

#define MAX_FRAMES_LIMIT            10000
#define MAX_FRAMES_LIMIT_AS_STRING "10000"

static VALUE missing_string = Qnil;

// Used as scratch space during sampling
struct sampling_buffer {
  unsigned int max_frames;
  VALUE *stack_buffer;
  int *lines_buffer;
  bool *is_ruby_frame;
  ddprof_ffi_Location *locations;
  ddprof_ffi_Line *lines;
}; // Note: typedef'd in the header to sampling_buffer

static VALUE _native_sample(VALUE self, VALUE thread, VALUE recorder_instance, VALUE metric_values_hash, VALUE labels_array, VALUE max_frames);
static void maybe_add_placeholder_frames_omitted(VALUE thread, sampling_buffer* buffer, char *frames_omitted_message, int frames_omitted_message_size);
static void record_placeholder_stack_in_native_code(VALUE recorder_instance, ddprof_ffi_Slice_i64 metric_values, ddprof_ffi_Slice_label labels);

void collectors_stack_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_stack_class = rb_define_class_under(collectors_module, "Stack", rb_cObject);
  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(collectors_stack_class, "Testing");

  rb_define_singleton_method(testing_module, "_native_sample", _native_sample, 5);

  missing_string = rb_str_new2("");
  rb_global_variable(&missing_string);
}

// This method exists only to enable testing Datadog::Profiling::Collectors::Stack behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(DDTRACE_UNUSED VALUE _self, VALUE thread, VALUE recorder_instance, VALUE metric_values_hash, VALUE labels_array, VALUE max_frames) {
  ENFORCE_TYPE(metric_values_hash, T_HASH);
  ENFORCE_TYPE(labels_array, T_ARRAY);

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

  int max_frames_requested = NUM2INT(max_frames);
  if (max_frames_requested < 0) rb_raise(rb_eArgError, "Invalid max_frames: value must not be negative");

  sampling_buffer *buffer = sampling_buffer_new(max_frames_requested);

  sample_thread(
    thread,
    buffer,
    recorder_instance,
    (ddprof_ffi_Slice_i64) {.ptr = metric_values, .len = ENABLED_VALUE_TYPES_COUNT},
    (ddprof_ffi_Slice_label) {.ptr = labels, .len = labels_count}
  );

  sampling_buffer_free(buffer);

  return Qtrue;
}

void sample_thread(VALUE thread, sampling_buffer* buffer, VALUE recorder_instance, ddprof_ffi_Slice_i64 metric_values, ddprof_ffi_Slice_label labels) {
  int captured_frames = ddtrace_rb_profile_frames(
    thread,
    0 /* stack starting depth */,
    buffer->max_frames,
    buffer->stack_buffer,
    buffer->lines_buffer,
    buffer->is_ruby_frame
  );

  // Idea: Should we release the global vm lock (GVL) after we get the data from `rb_profile_frames`? That way other Ruby threads
  // could continue making progress while the sample was ingested into the profile.
  //
  // Other things to take into consideration if we go in that direction:
  // * Is it safe to call `rb_profile_frame_...` methods on things from the `stack_buffer` without the GVL acquired?
  // * We need to make `VALUE` references in the `stack_buffer` visible to the Ruby GC
  // * Should we move this into a different thread entirely?
  // * If we don't move it into a different thread, does releasing the GVL on a Ruby thread mean that we're introducing
  //   a new thread switch point where there previously was none?

  // Ruby does not give us path and line number for methods implemented using native code.
  // The convention in Kernel#caller_locations is to instead use the path and line number of the first Ruby frame
  // on the stack that is below (e.g. directly or indirectly has called) the native method.
  // Thus, we keep that frame here to able to replicate that behavior.
  // (This is why we also iterate the sampling buffers backwards below -- so that it's easier to keep the last_ruby_frame)
  VALUE last_ruby_frame = Qnil;
  int last_ruby_line = 0;

  if (captured_frames == PLACEHOLDER_STACK_IN_NATIVE_CODE) {
    record_placeholder_stack_in_native_code(recorder_instance, metric_values, labels);
    return;
  }

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
      // **IMPORTANT**: Be very careful when calling any `rb_profile_frame_...` API with a non-Ruby frame, as legacy
      // Rubies may assume that what's in a buffer will lead to a Ruby frame.
      //
      // In particular for Ruby 2.2 the buffer contains a Ruby string (see the notes on our custom
      // rb_profile_frames for Ruby 2.2) and CALLING **ANY** OF THOSE APIs ON IT WILL CAUSE INSTANT VM CRASHES

#ifndef USE_LEGACY_RB_PROFILE_FRAMES // Modern Rubies
      name = ddtrace_rb_profile_frame_method_name(buffer->stack_buffer[i]);
#else // Ruby < 2.3
      name = buffer->stack_buffer[i];
#endif

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

  // Used below; since we want to stack-allocate this, we must do it here rather than in maybe_add_placeholder_frames_omitted
  const int frames_omitted_message_size = sizeof(MAX_FRAMES_LIMIT_AS_STRING " frames omitted");
  char frames_omitted_message[frames_omitted_message_size];

  // If we filled up the buffer, some frames may have been omitted. In that case, we'll add a placeholder frame
  // with that info.
  if (captured_frames == (long) buffer->max_frames) {
    maybe_add_placeholder_frames_omitted(thread, buffer, frames_omitted_message, frames_omitted_message_size);
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

static void maybe_add_placeholder_frames_omitted(VALUE thread, sampling_buffer* buffer, char *frames_omitted_message, int frames_omitted_message_size) {
  ptrdiff_t frames_omitted = stack_depth_for(thread) - buffer->max_frames;

  if (frames_omitted == 0) return; // Perfect fit!

  // The placeholder frame takes over a space, so if 10 frames were left out and we consume one other space for the
  // placeholder, then 11 frames are omitted in total
  frames_omitted++;

  snprintf(frames_omitted_message, frames_omitted_message_size, "%td frames omitted", frames_omitted);

  // Important note: `frames_omitted_message` MUST have a lifetime that is at least as long as the call to
  // `record_sample`. So be careful where it gets allocated. (We do have tests for this, at least!)
  buffer->lines[buffer->max_frames - 1] = (ddprof_ffi_Line) {
    .function = (ddprof_ffi_Function) {
      .name = DDPROF_FFI_CHARSLICE_C(""),
      .filename = ((ddprof_ffi_CharSlice) {.ptr = frames_omitted_message, .len = strlen(frames_omitted_message)})
    },
    .line = 0,
  };
}

// Our custom rb_profile_frames returning PLACEHOLDER_STACK_IN_NATIVE_CODE is equivalent to when the
// Ruby `Thread#backtrace` API returns an empty array: we know that a thread is alive but we don't know what it's doing:
//
// 1. It can be starting up
//    ```
//    > Thread.new { sleep }.backtrace
//    => [] # <-- note the thread hasn't actually started running sleep yet, we got there first
//    ```
// 2. It can be running native code
//    ```
//    > t = Process.detach(fork { sleep })
//    => #<Process::Waiter:0x00007ffe7285f7a0 run>
//    > t.backtrace
//    => [] # <-- this can happen even minutes later, e.g. it's not a race as in 1.
//    ```
//    This effect has been observed in threads created by the Iodine web server and the ffi gem,
//    see for instance https://github.com/ffi/ffi/pull/883 and https://github.com/DataDog/dd-trace-rb/pull/1719 .
//
// To give customers visibility into these threads, rather than reporting an empty stack, we replace the empty stack
// with one containing a placeholder frame, so that these threads are properly represented in the UX.
static void record_placeholder_stack_in_native_code(VALUE recorder_instance, ddprof_ffi_Slice_i64 metric_values, ddprof_ffi_Slice_label labels) {
  ddprof_ffi_Line placeholder_stack_in_native_code_line = {
    .function = (ddprof_ffi_Function) {
      .name = DDPROF_FFI_CHARSLICE_C(""),
      .filename = DDPROF_FFI_CHARSLICE_C("In native code")
    },
    .line = 0
  };
  ddprof_ffi_Location placeholder_stack_in_native_code_location =
    {.lines = (ddprof_ffi_Slice_line) {.ptr = &placeholder_stack_in_native_code_line, .len = 1}};

  record_sample(
    recorder_instance,
    (ddprof_ffi_Sample) {
      .locations = (ddprof_ffi_Slice_location) {.ptr = &placeholder_stack_in_native_code_location, .len = 1},
      .values = metric_values,
      .labels = labels,
    }
  );
}

sampling_buffer *sampling_buffer_new(unsigned int max_frames) {
  if (max_frames < 5) rb_raise(rb_eArgError, "Invalid max_frames: value must be >= 5");
  if (max_frames > MAX_FRAMES_LIMIT) rb_raise(rb_eArgError, "Invalid max_frames: value must be <= " MAX_FRAMES_LIMIT_AS_STRING);

  // Note: never returns NULL; if out of memory, it calls the Ruby out-of-memory handlers
  sampling_buffer* buffer = ruby_xcalloc(1, sizeof(sampling_buffer));

  buffer->max_frames = max_frames;

  buffer->stack_buffer  = ruby_xcalloc(max_frames, sizeof(VALUE));
  buffer->lines_buffer  = ruby_xcalloc(max_frames, sizeof(int));
  buffer->is_ruby_frame = ruby_xcalloc(max_frames, sizeof(bool));
  buffer->locations     = ruby_xcalloc(max_frames, sizeof(ddprof_ffi_Location));
  buffer->lines         = ruby_xcalloc(max_frames, sizeof(ddprof_ffi_Line));

  return buffer;
}

void sampling_buffer_free(sampling_buffer *buffer) {
  if (buffer == NULL) rb_raise(rb_eArgError, "sampling_buffer_free called with NULL buffer");

  ruby_xfree(buffer->stack_buffer);
  ruby_xfree(buffer->lines_buffer);
  ruby_xfree(buffer->is_ruby_frame);
  ruby_xfree(buffer->locations);
  ruby_xfree(buffer->lines);

  ruby_xfree(buffer);
}
