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

static VALUE missing_string = Qnil;

// Used as scratch space during sampling
struct sampling_buffer {
  uint16_t max_frames;
  ddog_prof_Location *locations;
  frame_info *stack_buffer;
}; // Note: typedef'd in the header to sampling_buffer

static VALUE _native_sample(
  VALUE self,
  VALUE thread,
  VALUE recorder_instance,
  VALUE metric_values_hash,
  VALUE labels_array,
  VALUE numeric_labels_array,
  VALUE max_frames,
  VALUE in_gc
);
static VALUE native_sample_do(VALUE args);
static VALUE native_sample_ensure(VALUE args);
static void maybe_add_placeholder_frames_omitted(VALUE thread, sampling_buffer* buffer, char *frames_omitted_message, int frames_omitted_message_size);
static void record_placeholder_stack_in_native_code(VALUE recorder_instance, sample_values values, sample_labels labels);
static void maybe_trim_template_random_ids(ddog_CharSlice *name_slice, ddog_CharSlice *filename_slice);

// These two functions are exposed as symbols by the VM but are not in any header.
// Their signatures actually take a `const rb_iseq_t *iseq` but it gets casted back and forth between VALUE.
extern VALUE rb_iseq_path(const VALUE);
extern VALUE rb_iseq_base_label(const VALUE);

void collectors_stack_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_stack_class = rb_define_class_under(collectors_module, "Stack", rb_cObject);
  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(collectors_stack_class, "Testing");

  rb_define_singleton_method(testing_module, "_native_sample", _native_sample, 7);

  missing_string = rb_str_new2("");
  rb_global_variable(&missing_string);
}

struct native_sample_args {
  VALUE in_gc;
  VALUE recorder_instance;
  sample_values values;
  sample_labels labels;
  VALUE thread;
  ddog_prof_Location *locations;
  sampling_buffer *buffer;
};

// This method exists only to enable testing Datadog::Profiling::Collectors::Stack behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(
  DDTRACE_UNUSED VALUE _self,
  VALUE thread,
  VALUE recorder_instance,
  VALUE metric_values_hash,
  VALUE labels_array,
  VALUE numeric_labels_array,
  VALUE max_frames,
  VALUE in_gc
) {
  ENFORCE_TYPE(metric_values_hash, T_HASH);
  ENFORCE_TYPE(labels_array, T_ARRAY);
  ENFORCE_TYPE(numeric_labels_array, T_ARRAY);

  VALUE zero = INT2NUM(0);
  VALUE heap_sample = rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("heap_sample"), Qfalse);
  ENFORCE_BOOLEAN(heap_sample);
  sample_values values = {
    .cpu_time_ns   = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("cpu-time"),      zero)),
    .cpu_or_wall_samples = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("cpu-samples"), zero)),
    .wall_time_ns  = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("wall-time"),     zero)),
    .alloc_samples = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("alloc-samples"), zero)),
    .alloc_samples_unscaled = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("alloc-samples-unscaled"), zero)),
    .timeline_wall_time_ns = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("timeline"), zero)),
    .heap_sample = heap_sample == Qtrue,
  };

  long labels_count = RARRAY_LEN(labels_array) + RARRAY_LEN(numeric_labels_array);
  ddog_prof_Label labels[labels_count];
  ddog_prof_Label *state_label = NULL;

  for (int i = 0; i < RARRAY_LEN(labels_array); i++) {
    VALUE key_str_pair = rb_ary_entry(labels_array, i);

    labels[i] = (ddog_prof_Label) {
      .key = char_slice_from_ruby_string(rb_ary_entry(key_str_pair, 0)),
      .str = char_slice_from_ruby_string(rb_ary_entry(key_str_pair, 1))
    };

    if (rb_str_equal(rb_ary_entry(key_str_pair, 0), rb_str_new_cstr("state"))) {
      state_label = &labels[i];
    }
  }
  for (int i = 0; i < RARRAY_LEN(numeric_labels_array); i++) {
    VALUE key_str_pair = rb_ary_entry(numeric_labels_array, i);

    labels[i + RARRAY_LEN(labels_array)] = (ddog_prof_Label) {
      .key = char_slice_from_ruby_string(rb_ary_entry(key_str_pair, 0)),
      .num = NUM2ULL(rb_ary_entry(key_str_pair, 1))
    };
  }

  int max_frames_requested = sampling_buffer_check_max_frames(NUM2INT(max_frames));

  ddog_prof_Location *locations = ruby_xcalloc(max_frames_requested, sizeof(ddog_prof_Location));
  sampling_buffer *buffer = sampling_buffer_new(max_frames_requested, locations);

  ddog_prof_Slice_Label slice_labels = {.ptr = labels, .len = labels_count};

  struct native_sample_args args_struct = {
    .in_gc = in_gc,
    .recorder_instance = recorder_instance,
    .values = values,
    .labels = (sample_labels) {.labels = slice_labels, .state_label = state_label},
    .thread = thread,
    .locations = locations,
    .buffer = buffer,
  };

  return rb_ensure(native_sample_do, (VALUE) &args_struct, native_sample_ensure, (VALUE) &args_struct);
}

static VALUE native_sample_do(VALUE args) {
  struct native_sample_args *args_struct = (struct native_sample_args *) args;

  if (args_struct->in_gc == Qtrue) {
    record_placeholder_stack(
      args_struct->recorder_instance,
      args_struct->values,
      args_struct->labels,
      DDOG_CHARSLICE_C("Garbage Collection")
    );
  } else {
    sample_thread(
      args_struct->thread,
      args_struct->buffer,
      args_struct->recorder_instance,
      args_struct->values,
      args_struct->labels
    );
  }

  return Qtrue;
}

static VALUE native_sample_ensure(VALUE args) {
  struct native_sample_args *args_struct = (struct native_sample_args *) args;

  ruby_xfree(args_struct->locations);
  sampling_buffer_free(args_struct->buffer);

  return Qtrue;
}

#define CHARSLICE_EQUALS(must_be_a_literal, charslice) (strlen("" must_be_a_literal) == charslice.len && strncmp(must_be_a_literal, charslice.ptr, charslice.len) == 0)

// Idea: Should we release the global vm lock (GVL) after we get the data from `rb_profile_frames`? That way other Ruby threads
// could continue making progress while the sample was ingested into the profile.
//
// Other things to take into consideration if we go in that direction:
// * Is it safe to call `rb_profile_frame_...` methods on things from the `stack_buffer` without the GVL acquired?
// * We need to make `VALUE` references in the `stack_buffer` visible to the Ruby GC
// * Should we move this into a different thread entirely?
// * If we don't move it into a different thread, does releasing the GVL on a Ruby thread mean that we're introducing
//   a new thread switch point where there previously was none?
void sample_thread(
  VALUE thread,
  sampling_buffer* buffer,
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels
) {
  int captured_frames = ddtrace_rb_profile_frames(
    thread,
    0 /* stack starting depth */,
    buffer->max_frames,
    buffer->stack_buffer
  );

  if (captured_frames == PLACEHOLDER_STACK_IN_NATIVE_CODE) {
    record_placeholder_stack_in_native_code(recorder_instance, values, labels);
    return;
  }

  // if (captured_frames > 0) {
  //   int cache_hits = 0;
  //   for (int i = 0; i < captured_frames; i++) {
  //     if (buffer->stack_buffer[i].same_frame) cache_hits++;
  //   }
  //   fprintf(stderr, "Sampling cache hits: %f\n", ((double) cache_hits / captured_frames) * 100);
  // }

  // Ruby does not give us path and line number for methods implemented using native code.
  // The convention in Kernel#caller_locations is to instead use the path and line number of the first Ruby frame
  // on the stack that is below (e.g. directly or indirectly has called) the native method.
  // Thus, we keep that frame here to able to replicate that behavior.
  // (This is why we also iterate the sampling buffers backwards below -- so that it's easier to keep the last_ruby_frame_filename)
  VALUE last_ruby_frame_filename = Qnil;
  int last_ruby_line = 0;

  ddog_prof_Label *state_label = labels.state_label;
  bool cpu_or_wall_sample = values.cpu_or_wall_samples > 0;
  bool has_cpu_time = cpu_or_wall_sample && values.cpu_time_ns > 0;
  bool only_wall_time = cpu_or_wall_sample && values.cpu_time_ns == 0 && values.wall_time_ns > 0;

  if (cpu_or_wall_sample && state_label == NULL) rb_raise(rb_eRuntimeError, "BUG: Unexpected missing state_label");

  if (has_cpu_time) state_label->str = DDOG_CHARSLICE_C("had cpu");

  for (int i = captured_frames - 1; i >= 0; i--) {
    VALUE name, filename;
    int line;

    if (buffer->stack_buffer[i].is_ruby_frame) {
      name = rb_iseq_base_label(buffer->stack_buffer[i].as.ruby_frame.iseq);
      filename = rb_iseq_path(buffer->stack_buffer[i].as.ruby_frame.iseq);
      line = buffer->stack_buffer[i].as.ruby_frame.line;

      last_ruby_frame_filename = filename;
      last_ruby_line = line;
    } else {
      name = rb_id2str(buffer->stack_buffer[i].as.native_frame.method_id);
      filename = last_ruby_frame_filename;
      line = last_ruby_line;
    }

    name = NIL_P(name) ? missing_string : name;
    filename = NIL_P(filename) ? missing_string : filename;

    ddog_CharSlice name_slice = char_slice_from_ruby_string(name);
    ddog_CharSlice filename_slice = char_slice_from_ruby_string(filename);

    maybe_trim_template_random_ids(&name_slice, &filename_slice);

    bool top_of_the_stack = i == 0;

    // When there's only wall-time in a sample, this means that the thread was not active in the sampled period.
    //
    // We try to categorize what it was doing based on what we observe at the top of the stack. This is a very rough
    // approximation, and in the future we hope to replace this with a more accurate approach (such as using the
    // GVL instrumentation API.)
    if (top_of_the_stack && only_wall_time) {
      if (!buffer->stack_buffer[i].is_ruby_frame) {
        // We know that known versions of Ruby implement these using native code; thus if we find a method with the
        // same name that is not native code, we ignore it, as it's probably a user method that coincidentally
        // has the same name. Thus, even though "matching just by method name" is kinda weak,
        // "matching by method name" + is native code seems actually to be good enough for a lot of cases.

        if (CHARSLICE_EQUALS("sleep", name_slice)) { // Expected to be Kernel.sleep
          state_label->str  = DDOG_CHARSLICE_C("sleeping");
        } else if (CHARSLICE_EQUALS("select", name_slice)) { // Expected to be Kernel.select
          state_label->str  = DDOG_CHARSLICE_C("waiting");
        } else if (
            CHARSLICE_EQUALS("synchronize", name_slice) || // Expected to be Monitor/Mutex#synchronize
            CHARSLICE_EQUALS("lock", name_slice) ||        // Expected to be Mutex#lock
            CHARSLICE_EQUALS("join", name_slice)           // Expected to be Thread#join
        ) {
          state_label->str  = DDOG_CHARSLICE_C("blocked");
        } else if (CHARSLICE_EQUALS("wait_readable", name_slice)) { // Expected to be IO#wait_readable
          state_label->str  = DDOG_CHARSLICE_C("network");
        }
        #ifdef NO_PRIMITIVE_POP // Ruby < 3.2
          else if (CHARSLICE_EQUALS("pop", name_slice)) { // Expected to be Queue/SizedQueue#pop
            state_label->str  = DDOG_CHARSLICE_C("waiting");
          }
        #endif
      } else {
        #ifndef NO_PRIMITIVE_POP // Ruby >= 3.2
          // Unlike the above, Ruby actually treats this one specially and gives it a nice file name we can match on!
          if (CHARSLICE_EQUALS("pop", name_slice) && CHARSLICE_EQUALS("<internal:thread_sync>", filename_slice)) { // Expected to be Queue/SizedQueue#pop
            state_label->str  = DDOG_CHARSLICE_C("waiting");
          }
        #endif
      }
    }

    buffer->locations[i] = (ddog_prof_Location) {
      .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C("")},
      .function = (ddog_prof_Function) {.name = name_slice, .filename = filename_slice},
      .line = line,
    };
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
    (ddog_prof_Slice_Location) {.ptr = buffer->locations, .len = captured_frames},
    values,
    labels
  );
}

// Rails's ActionView likes to dynamically generate method names with suffixed hashes/ids, resulting in methods with
// names such as:
// * "_app_views_layouts_explore_html_haml__2304485752546535910_211320" (__number_number suffix -- two underscores)
// * "_app_views_articles_index_html_erb___2022809201779434309_12900" (___number_number suffix -- three underscores)
// This makes these stacks not aggregate well, as well as being not-very-useful data.
// (Reference:
//  https://github.com/rails/rails/blob/4fa56814f18fd3da49c83931fa773caa727d8096/actionview/lib/action_view/template.rb#L389
//  The two vs three underscores happen when @identifier.hash is negative in that method: the "-" gets replaced with
//  the extra "_".)
//
// This method trims these suffixes, so that we keep less data + the names correctly aggregate together.
static void maybe_trim_template_random_ids(ddog_CharSlice *name_slice, ddog_CharSlice *filename_slice) {
  // Check filename doesn't end with ".rb"; templates are usually along the lines of .html.erb/.html.haml/...
  if (filename_slice->len < 3 || memcmp(filename_slice->ptr + filename_slice->len - 3, ".rb", 3) == 0) return;

  if (name_slice->len > 1024) return;

  int pos = ((int) name_slice->len) - 1;

  // Let's match on something__number_number:
  // Find start of id suffix from the end...
  if (name_slice->ptr[pos] < '0' || name_slice->ptr[pos] > '9') return;

  // ...now match a bunch of numbers and interspersed underscores
  for (int underscores = 0; pos >= 0 && underscores < 2; pos--) {
    if (name_slice->ptr[pos] == '_') underscores++;
    else if (name_slice->ptr[pos] < '0' || name_slice->ptr[pos] > '9') return;
  }

  // Make sure there's something left before the underscores (hence the <= instead of <) + match the last underscore
  if (pos <= 0 || name_slice->ptr[pos] != '_') return;

  // Does it have the optional third underscore? If so, remove it as well
  if (pos > 1 && name_slice->ptr[pos-1] == '_') pos--;

  // If we got here, we matched on our pattern. Let's slice the length of the string to exclude it.
  name_slice->len = pos;
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
  ddog_CharSlice function_name = DDOG_CHARSLICE_C("");
  ddog_CharSlice function_filename = {.ptr = frames_omitted_message, .len = strlen(frames_omitted_message)};
  buffer->locations[buffer->max_frames - 1] = (ddog_prof_Location) {
    .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C("")},
    .function = (ddog_prof_Function) {.name = function_name, .filename = function_filename},
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

static void record_placeholder_stack_in_native_code(
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels
) {
  record_placeholder_stack(
    recorder_instance,
    values,
    labels,
    DDOG_CHARSLICE_C("In native code")
  );
}

void record_placeholder_stack(
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels,
  ddog_CharSlice placeholder_stack
) {
  ddog_prof_Location placeholder_location = {
    .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C("")},
    .function = {.name = DDOG_CHARSLICE_C(""), .filename = placeholder_stack},
    .line = 0,
  };

  record_sample(
    recorder_instance,
    (ddog_prof_Slice_Location) {.ptr = &placeholder_location, .len = 1},
    values,
    labels
  );
}

uint16_t sampling_buffer_check_max_frames(int max_frames) {
  if (max_frames < 5) rb_raise(rb_eArgError, "Invalid max_frames: value must be >= 5");
  if (max_frames > MAX_FRAMES_LIMIT) rb_raise(rb_eArgError, "Invalid max_frames: value must be <= " MAX_FRAMES_LIMIT_AS_STRING);
  return max_frames;
}

sampling_buffer *sampling_buffer_new(uint16_t max_frames, ddog_prof_Location *locations) {
  sampling_buffer_check_max_frames(max_frames);

  // Note: never returns NULL; if out of memory, it calls the Ruby out-of-memory handlers
  sampling_buffer* buffer = ruby_xcalloc(1, sizeof(sampling_buffer));

  buffer->max_frames = max_frames;
  buffer->locations = locations;
  buffer->stack_buffer = ruby_xcalloc(max_frames, sizeof(frame_info));

  return buffer;
}

void sampling_buffer_free(sampling_buffer *buffer) {
  if (buffer == NULL) rb_raise(rb_eArgError, "sampling_buffer_free called with NULL buffer");

  // buffer->locations are owned by whoever called sampling_buffer_new, not us
  ruby_xfree(buffer->stack_buffer);

  ruby_xfree(buffer);
}
