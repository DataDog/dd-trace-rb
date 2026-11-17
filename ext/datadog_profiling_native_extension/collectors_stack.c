#include <ruby.h>
#include <ruby/debug.h>
#include <stdatomic.h>

#include "datadog_ruby_common.h"
#include "private_vm_api_access.h"
#include "ruby_helpers.h"
#include "stack_recorder.h"
#include "collectors_stack.h"

// An estimation of how much bytes we need on average for qualified method names.
// This is an "average" and not a "max" because frames can use more than that,
// we just fall back to unqualified method names if the buffer is full.
#define QUALIFIED_NAME_AVG_SIZE 64

// Gathers stack traces from running threads, storing them in a StackRecorder instance
// This file implements the native bits of the Datadog::Profiling::Collectors::Stack class

static VALUE _native_ruby_native_filename(DDTRACE_UNUSED VALUE self);
static VALUE _native_sample(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE native_sample_do(VALUE args);
static VALUE native_sample_ensure(VALUE args);
static void set_file_info_for_cfunc(
  ddog_CharSlice *filename_slice,
  int *line,
  ddog_CharSlice last_ruby_frame_filename,
  int last_ruby_line,
  native_function_pointer function,
  bool top_of_the_stack,
  bool native_filenames_enabled,
  native_filenames_cache *filename_cache
);
static void add_truncated_frames_placeholder(ddog_prof_Location *locations);
static void record_placeholder_stack_in_native_code(VALUE recorder_instance, sample_values values, sample_labels labels);
static void maybe_trim_template_random_ids(ddog_CharSlice *frame_name, ddog_CharSlice filename, bool frame_name_in_scratch_buffer);

void collectors_stack_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_stack_class = rb_define_class_under(collectors_module, "Stack", rb_cObject);

  rb_define_singleton_method(collectors_stack_class, "_native_ruby_native_filename", _native_ruby_native_filename, 0);

  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(collectors_stack_class, "Testing");

  rb_define_singleton_method(testing_module, "_native_sample", _native_sample, -1);
  rb_define_singleton_method(testing_module, "_native_resolve_filename", native_filenames_testing_resolve, 1);
}

static VALUE _native_ruby_native_filename(DDTRACE_UNUSED VALUE self) {
  return native_filenames_ruby_filename();
}

typedef struct {
  VALUE in_gc;
  VALUE recorder_instance;
  sample_values values;
  sample_labels labels;
  VALUE thread;
  sample_locations locations;
  sampling_buffer *buffer;
  bool native_filenames_enabled;
  native_filenames_cache native_filenames_cache;
  bool show_classes;
} native_sample_args;

// This method exists only to enable testing Datadog::Profiling::Collectors::Stack behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self) {
  // Positional args
  VALUE thread;
  VALUE recorder_instance;
  VALUE metric_values_hash;
  VALUE labels_array;
  VALUE numeric_labels_array;
  VALUE options;

  rb_scan_args(argc, argv, "5:", &thread, &recorder_instance, &metric_values_hash, &labels_array, &numeric_labels_array, &options);

  if (options == Qnil) options = rb_hash_new();

  // Optional keyword args
  VALUE max_frames = rb_hash_lookup2(options, ID2SYM(rb_intern("max_frames")), INT2NUM(400));
  VALUE in_gc = rb_hash_lookup2(options, ID2SYM(rb_intern("in_gc")), Qfalse);
  VALUE is_gvl_waiting_state = rb_hash_lookup2(options, ID2SYM(rb_intern("is_gvl_waiting_state")), Qfalse);
  VALUE native_filenames_enabled = rb_hash_lookup2(options, ID2SYM(rb_intern("native_filenames_enabled")), Qfalse);
  VALUE show_classes = rb_hash_lookup2(options, ID2SYM(rb_intern("show_classes")), Qtrue);

  ENFORCE_TYPE(metric_values_hash, T_HASH);
  ENFORCE_TYPE(labels_array, T_ARRAY);
  ENFORCE_TYPE(numeric_labels_array, T_ARRAY);
  ENFORCE_TYPE(max_frames, T_FIXNUM);
  ENFORCE_BOOLEAN(in_gc);
  ENFORCE_BOOLEAN(is_gvl_waiting_state);
  ENFORCE_BOOLEAN(native_filenames_enabled);
  ENFORCE_BOOLEAN(show_classes);

  VALUE zero = INT2NUM(0);
  // Pass `heap_sample: {new_object: ..., alloc_class: ...}` to also record this sample for heap profiling
  VALUE heap_sample_options = rb_hash_lookup2(options, ID2SYM(rb_intern("heap_sample")), Qnil);
  heap_sample_values heap_sample = {};
  if (heap_sample_options != Qnil) {
    ENFORCE_TYPE(heap_sample_options, T_HASH);
    heap_sample.new_object = rb_hash_fetch(heap_sample_options, ID2SYM(rb_intern("new_object")));
    heap_sample.alloc_class =
      char_slice_from_ruby_string(rb_hash_fetch(heap_sample_options, ID2SYM(rb_intern("alloc_class"))));
  }

  sample_values values = {
    .cpu_time_ns   = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("cpu-time"),      zero)),
    .cpu_or_wall_samples = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("cpu-samples"), zero)),
    .wall_time_ns  = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("wall-time"),     zero)),
    .alloc_samples = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("alloc-samples"), zero)),
    .alloc_samples_unscaled = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("alloc-samples-unscaled"), zero)),
    .timeline_wall_time_ns = NUM2UINT(rb_hash_lookup2(metric_values_hash, rb_str_new_cstr("timeline"), zero)),
    .heap_sample = heap_sample_options != Qnil ? &heap_sample : NULL,
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

  sample_locations locations;
  sample_locations_initialize(&locations, max_frames_requested, show_classes == Qtrue);
  sampling_buffer buffer;
  sampling_buffer_initialize(&buffer, max_frames_requested, show_classes == Qtrue);

  ddog_prof_Slice_Label slice_labels = {.ptr = labels, .len = labels_count};

  native_sample_args args_struct = {
    .in_gc = in_gc,
    .recorder_instance = recorder_instance,
    .values = values,
    .labels = (sample_labels) {.labels = slice_labels, .state_label = state_label, .is_gvl_waiting_state = is_gvl_waiting_state == Qtrue},
    .thread = thread,
    .locations = locations,
    .buffer = &buffer,
    .native_filenames_enabled = native_filenames_enabled == Qtrue,
    .show_classes = show_classes == Qtrue,
  };

  native_filenames_cache_init(&args_struct.native_filenames_cache);

  return rb_ensure(native_sample_do, (VALUE) &args_struct, native_sample_ensure, (VALUE) &args_struct);
}

static VALUE native_sample_do(VALUE args) {
  native_sample_args *args_struct = (native_sample_args *) args;

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
      args_struct->locations,
      args_struct->recorder_instance,
      args_struct->values,
      args_struct->labels,
      args_struct->native_filenames_enabled,
      &args_struct->native_filenames_cache,
      args_struct->show_classes
    );
  }

  return Qtrue;
}

static VALUE native_sample_ensure(VALUE args) {
  native_sample_args *args_struct = (native_sample_args *) args;

  sample_locations_free(&args_struct->locations);
  sampling_buffer_free(args_struct->buffer);
  native_filenames_cache_cleanup(&args_struct->native_filenames_cache);

  return Qtrue;
}

#define CHARSLICE_EQUALS(must_be_a_literal, charslice) (strlen("" must_be_a_literal) == charslice.len && strncmp(must_be_a_literal, charslice.ptr, charslice.len) == 0)

// The method name on its own, without any class/module name
static inline ddog_CharSlice unqualified_name(const rb_callable_method_entry_t *cme, const rb_iseq_t *iseq) {
  VALUE name = ddtrace_location_base_label(cme, iseq);
  return (name == Qfalse) ? DDOG_CHARSLICE_C("") : char_slice_from_ruby_string(name);
}

// When there's only wall-time in a sample, this means that the thread was not active in the sampled period, so we try
// to tell what it was doing instead.
//
// TODO: `method` is the unqualified method name
// because we don't always use qualified method names yet,
// and the checks below need something stable to compare to until we always do.
static void categorize_sample_state(
  sample_labels labels,
  frame_info frame,
  ddog_CharSlice method,
  DDTRACE_UNUSED ddog_CharSlice filename
) {
  ddog_prof_Label *state_label = labels.state_label;

  // Did the caller already provide the state?
  if (labels.is_gvl_waiting_state) {
    state_label->str = DDOG_CHARSLICE_C("waiting for gvl");

  // Otherwise, we try to categorize what the thread was doing based on what we observe at the top of the stack. This is a very rough
  // approximation, and in the future we hope to replace this with a more accurate approach (such as using the
  // GVL instrumentation API.)
  } else if (!frame.is_ruby_frame) {
    // We know that known versions of Ruby implement these using native code; thus if we find a method with the
    // same name that is not native code, we ignore it, as it's probably a user method that coincidentally
    // has the same name. Thus, even though "matching just by method name" is kinda weak,
    // "matching by method name" + is native code seems actually to be good enough for a lot of cases.

    if (CHARSLICE_EQUALS("sleep", method)) { // Expected to be Kernel.sleep
      state_label->str  = DDOG_CHARSLICE_C("sleeping");
    } else if (CHARSLICE_EQUALS("select", method)) { // Expected to be Kernel.select
      state_label->str  = DDOG_CHARSLICE_C("waiting");
    } else if (
        CHARSLICE_EQUALS("synchronize", method) || // Expected to be Monitor/Mutex#synchronize on Ruby 2 & 3, and Monitor#synchronize on 4 (Mutex becomes <internal:thread_sync>)
        #ifdef NO_PRIMITIVE_MUTEX_AND_CONDITION_VARIABLE // Ruby < 4
          CHARSLICE_EQUALS("lock", method) ||        // Expected to be Mutex#lock
        #endif
        CHARSLICE_EQUALS("join", method)           // Expected to be Thread#join
    ) {
      state_label->str  = DDOG_CHARSLICE_C("blocked");
    } else if (CHARSLICE_EQUALS("wait_readable", method)) { // Expected to be IO#wait_readable
      state_label->str  = DDOG_CHARSLICE_C("network");
    } else if (CHARSLICE_EQUALS("_native_idle_sampling_loop", method)) { // Expected to be Datadog::Profiler::Collectors::IdleSamplingHelper#_native_idle_sampling_loop
      state_label->str  = DDOG_CHARSLICE_C("waiting");
    } else if (CHARSLICE_EQUALS("_native_sampling_loop", method)) { // Expected to be Datadog::Profiler::Collectors::CpuAndWallTimeWorker#_native_sampling_loop
      state_label->str  = DDOG_CHARSLICE_C("sleeping");
    }
    #ifdef NO_PRIMITIVE_POP // Ruby < 3.2
      else if (CHARSLICE_EQUALS("pop", method)) { // Expected to be Queue/SizedQueue#pop
        state_label->str  = DDOG_CHARSLICE_C("waiting");
      }
    #endif
  } else {
    #ifndef NO_PRIMITIVE_POP // Ruby >= 3.2
      if (CHARSLICE_EQUALS("<internal:thread_sync>", filename)) {
        if (CHARSLICE_EQUALS("pop", method)) { // Expected to be Queue/SizedQueue#pop
          state_label->str  = DDOG_CHARSLICE_C("waiting");
        }
        #ifndef NO_PRIMITIVE_MUTEX_AND_CONDITION_VARIABLE // Ruby >= 4
          else if (CHARSLICE_EQUALS("synchronize", method) || CHARSLICE_EQUALS("lock", method)) { // Expected to be Mutex#lock/synchronize
            state_label->str  = DDOG_CHARSLICE_C("blocked");
          } else if (CHARSLICE_EQUALS("sleep", method)) { // Expected to be Mutex#sleep
            state_label->str  = DDOG_CHARSLICE_C("sleeping");
          } else if (CHARSLICE_EQUALS("wait", method)) { // Expected to be ConditionVariable#wait
            state_label->str  = DDOG_CHARSLICE_C("waiting");
          }
        #endif
      }
    #endif
  }
}

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
  sample_locations locations,
  VALUE recorder_instance,
  sample_values values,
  sample_labels labels,
  bool native_filenames_enabled,
  native_filenames_cache *filename_cache,
  bool show_classes
) {
  if (buffer->max_frames != locations.len) {
    // This shouldn't happen as thread_context_collector_reset_all_per_thread_contexts (which resizes every
    // per-thread sampling buffer to match the collector's max_frames) must always be called before starting or
    // restarting profiling.
    raise_error(
      rb_eRuntimeError,
      "Unexpected: sampling buffer max_frames (%d) doesn't match locations len (%d)",
      (int) buffer->max_frames,
      (int) locations.len
    );
  }

  // Prepared stacks belong to CPU/wall-time samples; other sample types need the stack at their event site.
  // We deliberately discard any pending stack (including GVL-wait captures) to reuse this buffer;
  // the later CPU/wall-time sample will capture a fresh stack.
  // In practice it should be very rare that we didn't get the chance to flush a cpu/wall-time sample
  // before the next allocation happened.
  if (values.cpu_or_wall_samples == 0 || !buffer->pending_sample) {
    prepare_sample_thread(thread, buffer);
  }

  int captured_frames = buffer->pending_sample_result;

  if (captured_frames == PLACEHOLDER_STACK_IN_NATIVE_CODE) {
    record_placeholder_stack_in_native_code(recorder_instance, values, labels);

    // Done reading from the buffer -- allow GC to stop marking it.
    buffer->pending_sample = false;
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
  // (This is why we also iterate the sampling buffers backwards from what libdatadog uses below -- so that it's easier
  // to keep the last_ruby_frame_filename)
  ddog_CharSlice last_ruby_frame_filename = DDOG_CHARSLICE_C("");
  int last_ruby_line = 0;

  ddog_prof_Label *state_label = labels.state_label;
  bool cpu_or_wall_sample = values.cpu_or_wall_samples > 0;
  bool has_cpu_time = cpu_or_wall_sample && values.cpu_time_ns > 0;
  // Note: In theory, a cpu_or_wall_sample should always have some wall-time. In practice, the first sample for a thread
  // will be zero, as well as if the system clock does something weird. Thus, at some point we had values.wall_time_ns > 0
  // here, but >= 0 makes this easier to understand/debug.
  bool only_wall_time = cpu_or_wall_sample && values.cpu_time_ns == 0 && values.wall_time_ns >= 0;

  if (cpu_or_wall_sample && state_label == NULL) raise_error(rb_eRuntimeError, "BUG: Unexpected missing state_label");

  if (has_cpu_time) {
    state_label->str = DDOG_CHARSLICE_C("had cpu");
    if (labels.is_gvl_waiting_state) raise_error(rb_eRuntimeError, "BUG: Unexpected combination of cpu-time with is_gvl_waiting");
  }

  int top_of_stack_position = captured_frames - 1;
  char *qualified_name_buf = locations.qualified_name_buf;
  size_t qualified_name_buf_size = locations.qualified_name_buf_size;

  for (int i = 0; i <= top_of_stack_position; i++) {
    ddog_CharSlice filename_slice;
    int line;
    bool top_of_the_stack = i == top_of_stack_position;

    frame_info frame = buffer->stack_buffer[i];
    const rb_callable_method_entry_t *cme = frame.cme;
    const rb_iseq_t* iseq;
    if (frame.is_ruby_frame) {
      iseq = frame.as.ruby_frame.iseq;

      VALUE filename = ddtrace_iseq_path(iseq);
      filename_slice = char_slice_from_ruby_string(filename);
      line = frame.as.ruby_frame.line;

      last_ruby_frame_filename = filename_slice;
      last_ruby_line = line;
    } else {
      iseq = NULL;

      set_file_info_for_cfunc(
        &filename_slice,
        &line,
        last_ruby_frame_filename,
        last_ruby_line,
        (native_function_pointer) ddtrace_cme_cfunc_func(cme),
        top_of_the_stack,
        native_filenames_enabled,
        filename_cache
      );
    }

    // This frame kept the name we composed for it in an earlier sample, so there's nothing to compose or trim again
    char *cached_name = buffer->cached_names == NULL ? NULL : buffer->cached_names + (i * MAX_CACHED_FRAME_NAME);
    // The length is only ever set together with the name it describes, and frames start out zeroed
    bool name_is_cached = frame.cached_name_len > 0;

    ddog_CharSlice frame_name;
    // We only keep a name we managed to compose: ddtrace_location_label() also fails when this stack used up the
    // scratch buffer, and keeping the unqualified name it falls back to would stick to the frame even once there's
    // room for it again.
    bool name_is_cacheable = false;
    if (name_is_cached) {
      frame_name = (ddog_CharSlice) {.ptr = cached_name, .len = frame.cached_name_len};
    } else if (show_classes) {
      ssize_t written = ddtrace_location_label(cme, iseq, qualified_name_buf, qualified_name_buf_size);
      if (written > 0) {
        frame_name = (ddog_CharSlice) {.ptr = qualified_name_buf, .len = written};
        qualified_name_buf += written;
        qualified_name_buf_size -= written;
        name_is_cacheable = true;
      } else {
        frame_name = unqualified_name(cme, iseq); // just the method name
      }
    } else {
      frame_name = unqualified_name(cme, iseq);
    }

    if (top_of_the_stack && only_wall_time) {
      categorize_sample_state(labels, frame, unqualified_name(cme, iseq), filename_slice);
    }

    if (!name_is_cached) {
      maybe_trim_template_random_ids(&frame_name, filename_slice, name_is_cacheable);

      // Keep this name for as long as the frame stays in the buffer
      if (cached_name != NULL && name_is_cacheable && frame_name.len <= MAX_CACHED_FRAME_NAME) {
        memcpy(cached_name, frame_name.ptr, frame_name.len);
        buffer->stack_buffer[i].cached_name_len = frame_name.len;
      }
    }

    int libdatadog_stores_stacks_flipped_from_rb_profile_frames_index = top_of_stack_position - i;

    locations.ptr[libdatadog_stores_stacks_flipped_from_rb_profile_frames_index] = (ddog_prof_Location) {
      .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
      .function = (ddog_prof_Function) {.name = frame_name, .filename = filename_slice},
      .line = line,
    };
  }

  // If we filled up the locations, some frames may have been omitted. In that case, we'll add a placeholder frame
  // with that info.
  if (captured_frames == (long) locations.len) {
    add_truncated_frames_placeholder(locations.ptr);
  }

  record_sample(
    recorder_instance,
    (ddog_prof_Slice_Location) {.ptr = locations.ptr, .len = captured_frames},
    values,
    labels
  );

  // Done reading from the buffer -- allow GC to stop marking it.
  // This needs to be done last in this function in case anything above triggers a GC
  // (remember that `ruby_xmalloc` for instance can do that too...)
  buffer->pending_sample = false;
}

static void set_file_info_for_cfunc(
  ddog_CharSlice *filename_slice,
  int *line,
  ddog_CharSlice last_ruby_frame_filename,
  int last_ruby_line,
  native_function_pointer function,
  bool top_of_the_stack,
  bool native_filenames_enabled,
  native_filenames_cache *filename_cache
) {
  if (native_filenames_enabled) {
    native_filename filename = native_filenames_lookup(filename_cache, function);
    if (filename.path[0] != '\0' &&
      // TODO: Using the ruby_native_filename at the top of the stack has a weird effect on the "top methods" table because
      // e.g. we don't have classnames for methods. This is especially visible in the allocations profile, e.g.
      // what a surprise, you're telling me "libruby.so:new" is the top method always?
      // Until we have a better way of dealing with that, we don't do this replacement for the top frame.
      // (Bonus TODO note: This might be fixed by using full class/module names in frames?)
      (!filename.is_ruby || !top_of_the_stack)
    ) {
      *filename_slice = (ddog_CharSlice) {.ptr = filename.path, .len = strlen(filename.path)};
      // Explicitly set the line to 0 as it has no meaning on a native library (e.g. an .so is built of many source files)
      // and anyway often that debug info is not available.
      *line = 0;
      return;
    }
  }

  *filename_slice = last_ruby_frame_filename;
  *line = last_ruby_line;
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
//
// The ids end `frame_name`, or sit right before DDTRACE_BLOCK_SUFFIX
// ("Foo#_app_views_articles_index_html_erb__123_456 (block)"); in that case we move the suffix left over the ids.
// That write needs a name we composed ourselves, which is what `frame_name_in_scratch_buffer` tells us.
static void maybe_trim_template_random_ids(
  ddog_CharSlice *frame_name,
  ddog_CharSlice filename,
  bool frame_name_in_scratch_buffer
) {
  // Check filename doesn't end with ".rb"; templates are usually along the lines of .html.erb/.html.haml/...
  if (filename.len < 3 || memcmp(filename.ptr + filename.len - 3, ".rb", 3) == 0) return;

  if (frame_name->len > 1024) return;
  if (frame_name->len == 0) return;

  static const char block_suffix[] = DDTRACE_BLOCK_SUFFIX;
  size_t block_suffix_len = sizeof(block_suffix) - 1;

  size_t len = frame_name->len;
  bool has_block_suffix =
    frame_name_in_scratch_buffer &&
    len > block_suffix_len &&
    memcmp(frame_name->ptr + len - block_suffix_len, block_suffix, block_suffix_len) == 0;
  if (has_block_suffix) len -= block_suffix_len;

  int pos = ((int) len) - 1;

  // Let's match on something__number_number:
  // Find start of id suffix from the end...
  if (frame_name->ptr[pos] < '0' || frame_name->ptr[pos] > '9') return;

  // ...now match a bunch of numbers and interspersed underscores
  for (int underscores = 0; pos >= 0 && underscores < 2; pos--) {
    if (frame_name->ptr[pos] == '_') underscores++;
    else if (frame_name->ptr[pos] < '0' || frame_name->ptr[pos] > '9') return;
  }

  // Make sure there's something left before the underscores (hence the <= instead of <) + match the last underscore
  if (pos <= 0 || frame_name->ptr[pos] != '_') return;

  // Does it have the optional third underscore? If so, remove it as well
  if (pos > 1 && frame_name->ptr[pos-1] == '_') pos--;

  // If we got here, we matched on our pattern. Let's slice the length of the string to exclude it.
  if (has_block_suffix) {
    memcpy((char *) frame_name->ptr + pos, block_suffix, block_suffix_len);
    frame_name->len = pos + block_suffix_len;
  } else {
    frame_name->len = pos;
  }
}

static void add_truncated_frames_placeholder(ddog_prof_Location *locations) {
  // Important note: The strings below are static so we don't need to worry about their lifetime. If we ever want to change
  // this to non-static strings, don't forget to check that lifetimes are properly respected.
  locations[0] = (ddog_prof_Location) {
    .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
    .function = {.name = DDOG_CHARSLICE_C("Truncated Frames"), .filename = DDOG_CHARSLICE_C(""), .filename_id = {}},
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
    .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
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

// Also called from a signal handler or during GC; check callers' safety requirements before changing this function.
bool prepare_sample_thread(VALUE thread, sampling_buffer *buffer) {
  // While the signal handler checks if there's GC going on, it's actually possible for `sampling_buffer_mark` to
  // still run outside of GC (see comments on that function) and thus we guard for it here.
  if (buffer->is_marking) return false;

  buffer->pending_sample = true;
  buffer->pending_sample_result = ddtrace_rb_profile_frames(thread, 0, buffer->max_frames, buffer->stack_buffer, false);
  return true;
}

void sample_locations_initialize(sample_locations *locations, uint16_t max_frames, bool show_classes) {
  locations->len = max_frames;
  locations->ptr = ruby_xcalloc(max_frames, sizeof(ddog_prof_Location));
  if (show_classes) {
    locations->qualified_name_buf_size = QUALIFIED_NAME_AVG_SIZE * max_frames;
    locations->qualified_name_buf = ruby_xmalloc(locations->qualified_name_buf_size);
  } else {
    locations->qualified_name_buf_size = 0;
    locations->qualified_name_buf = NULL;
  }
}

void sample_locations_free(sample_locations *locations) {
  ruby_xfree(locations->ptr);
  ruby_xfree(locations->qualified_name_buf);

  locations->ptr = NULL;
  locations->len = 0;
  locations->qualified_name_buf = NULL;
  locations->qualified_name_buf_size = 0;
}

uint16_t sampling_buffer_check_max_frames(int max_frames) {
  if (max_frames < MIN_FRAMES_LIMIT) raise_error(rb_eArgError, "Invalid max_frames: value must be >= " MIN_FRAMES_LIMIT_AS_STRING);
  if (max_frames > MAX_FRAMES_LIMIT) raise_error(rb_eArgError, "Invalid max_frames: value must be <= " MAX_FRAMES_LIMIT_AS_STRING);
  return max_frames;
}

void sampling_buffer_initialize(sampling_buffer *buffer, uint16_t max_frames, bool cache_names) {
  sampling_buffer_check_max_frames(max_frames);

  buffer->max_frames = max_frames;
  buffer->stack_buffer = ruby_xcalloc(max_frames, sizeof(frame_info));
  buffer->pending_sample = false;
  buffer->is_marking = false;
  buffer->pending_sample_result = 0;
  buffer->cached_names = cache_names ? ruby_xcalloc(max_frames, MAX_CACHED_FRAME_NAME) : NULL;
}

void sampling_buffer_free(sampling_buffer *buffer) {
  ruby_xfree(buffer->stack_buffer);
  ruby_xfree(buffer->cached_names);

  buffer->max_frames = 0;
  buffer->stack_buffer = NULL;
  buffer->pending_sample = false;
  buffer->is_marking = false;
  buffer->pending_sample_result = 0;
  buffer->cached_names = NULL;
}

void sampling_buffer_mark(sampling_buffer *buffer) {
  if (!sampling_buffer_needs_marking(buffer)) {
    rb_bug("sampling_buffer_mark called with no pending sample. `sampling_buffer_needs_marking` should be used before calling mark.");
  }

  buffer->is_marking = true;
  // The sampling buffer isn't supposed to be touched during GC. Yet, marking can happen outside of GC -- in particular
  // ObjectSpace.dump/dump_all and reachable_objects_from invoke mark callbacks outside GC to enumerate references.
  // Thus we keep this flag to tell the signal handler "hey you're still not allowed to touch the buffer at this time".
  //
  // The fences ensure the compiler doesn't reorder the flags and a signal handler observes them
  // See https://github.com/ruby/ruby/pull/11036 for a similar change made to the Ruby VM with more context.
  atomic_signal_fence(memory_order_seq_cst);

  for (int i = 0; i < buffer->pending_sample_result; i++) {
    rb_gc_mark((VALUE) buffer->stack_buffer[i].cme);
    if (buffer->stack_buffer[i].is_ruby_frame) {
      rb_gc_mark((VALUE) buffer->stack_buffer[i].as.ruby_frame.iseq);
    }
  }

  // Make sure iteration completes before `is_marking` is unset...
  atomic_signal_fence(memory_order_seq_cst);
  buffer->is_marking = false;
}
