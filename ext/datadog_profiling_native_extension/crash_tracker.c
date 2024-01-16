#include <ruby.h>
#include <datadog/common.h>
#include <libdatadog_helpers.h>

static VALUE _native_start_crashtracker(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);

// Used to report Ruby VM crashes.
// Once initialized, segfaults will be reported automatically using libdatadog.

void crash_tracker_init(VALUE profiling_module) {
  VALUE crash_tracker_class = rb_define_class_under(profiling_module, "CrashTracker", rb_cObject);

  rb_define_singleton_method(crash_tracker_class, "_native_start_crashtracker", _native_start_crashtracker, -1);
}

static VALUE _native_start_crashtracker(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);

  VALUE exporter_configuration = rb_hash_fetch(options, ID2SYM(rb_intern("exporter_configuration")));
  VALUE path_to_crashtracking_receiver_binary = rb_hash_fetch(options, ID2SYM(rb_intern("path_to_crashtracking_receiver_binary")));
  VALUE tags_as_array = rb_hash_fetch(options, ID2SYM(rb_intern("tags_as_array")));

  ENFORCE_TYPE(exporter_configuration, T_ARRAY);
  ENFORCE_TYPE(tags_as_array, T_ARRAY);
  ENFORCE_TYPE(path_to_crashtracking_receiver_binary, T_STRING);

  VALUE version = ddtrace_version();
  ddog_Endpoint endpoint = endpoint_from(exporter_configuration);

  // This needs to come last, after all things that can raise exceptions, as otherwise it can leak
  ddog_Vec_Tag tags = convert_tags(tags_as_array);

  ddog_prof_Configuration config = {
    .create_alt_stack = false, // This breaks the Ruby VM's stack overflow detection
    .endpoint = endpoint,
    .path_to_receiver_binary = char_slice_from_ruby_string(path_to_crashtracking_receiver_binary),
  };

  ddog_prof_Metadata metadata = {
    .profiling_library_name = DDOG_CHARSLICE_C("dd-trace-rb"),
    .profiling_library_version = char_slice_from_ruby_string(version),
    .family = DDOG_CHARSLICE_C("ruby"),
    .tags = &tags,
  };

  ddog_prof_Profile_Result result = ddog_prof_crashtracker_init(config, metadata);

  // Clean up before potentially raising any exceptions
  ddog_Vec_Tag_drop(tags);

  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to initialize the crash tracker: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}
