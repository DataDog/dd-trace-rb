#include <ruby.h>
#include <datadog/common.h>
#include <libdatadog_helpers.h>

static VALUE _native_start_or_update_on_fork(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_stop(DDTRACE_UNUSED VALUE _self);

// Used to report Ruby VM crashes.
// Once initialized, segfaults will be reported automatically using libdatadog.

void crashtracker_init(VALUE profiling_module) {
  VALUE crashtracker_class = rb_define_class_under(profiling_module, "Crashtracker", rb_cObject);

  rb_define_singleton_method(crashtracker_class, "_native_start_or_update_on_fork", _native_start_or_update_on_fork, -1);
  rb_define_singleton_method(crashtracker_class, "_native_stop", _native_stop, 0);
}

static VALUE _native_start_or_update_on_fork(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);

  VALUE exporter_configuration = rb_hash_fetch(options, ID2SYM(rb_intern("exporter_configuration")));
  VALUE path_to_crashtracking_receiver_binary = rb_hash_fetch(options, ID2SYM(rb_intern("path_to_crashtracking_receiver_binary")));
  VALUE tags_as_array = rb_hash_fetch(options, ID2SYM(rb_intern("tags_as_array")));
  VALUE action = rb_hash_fetch(options, ID2SYM(rb_intern("action")));
  VALUE start_action = ID2SYM(rb_intern("start"));
  VALUE update_on_fork_action = ID2SYM(rb_intern("update_on_fork"));

  ENFORCE_TYPE(exporter_configuration, T_ARRAY);
  ENFORCE_TYPE(tags_as_array, T_ARRAY);
  ENFORCE_TYPE(path_to_crashtracking_receiver_binary, T_STRING);
  ENFORCE_TYPE(action, T_SYMBOL);

  if (action != start_action && action != update_on_fork_action) rb_raise(rb_eArgError, "Unexpected action: %+"PRIsVALUE, action);

  VALUE version = ddtrace_version();
  ddog_Endpoint endpoint = endpoint_from(exporter_configuration);

  // This needs to come last, after all things that can raise exceptions, as otherwise it can leak
  ddog_Vec_Tag tags = convert_tags(tags_as_array);

  ddog_prof_CrashtrackerConfiguration config = {
    .create_alt_stack = false, // This breaks the Ruby VM's stack overflow detection
    .endpoint = endpoint,
    .path_to_receiver_binary = char_slice_from_ruby_string(path_to_crashtracking_receiver_binary),
    .resolve_frames = DDOG_PROF_CRASHTRACKER_RESOLVE_FRAMES_NEVER, // TODO: Enable && validate frame resolving
  };

  ddog_prof_CrashtrackerMetadata metadata = {
    .profiling_library_name = DDOG_CHARSLICE_C("dd-trace-rb"),
    .profiling_library_version = char_slice_from_ruby_string(version),
    .family = DDOG_CHARSLICE_C("ruby"),
    .tags = &tags,
  };

  ddog_prof_Profile_Result result =
    action == start_action ?
      ddog_prof_crashtracker_init(config, metadata) :
      ddog_prof_crashtracker_update_on_fork(config, metadata);

  // Clean up before potentially raising any exceptions
  ddog_Vec_Tag_drop(tags);

  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to start/update the crash tracker: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}

static VALUE _native_stop(DDTRACE_UNUSED VALUE _self) {
  ddog_prof_Profile_Result result = ddog_prof_crashtracker_shutdown();

  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to stop the crash tracker: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}
