#include <ruby.h>
#include <datadog/profiling.h>

#include "datadog_ruby_common.h"

static VALUE _native_start_or_update_on_fork(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_stop(DDTRACE_UNUSED VALUE _self);
static void crashtracker_init(VALUE profiling_module);

// Used to report Ruby VM crashes.
// Once initialized, segfaults will be reported automatically using libdatadog.

void DDTRACE_EXPORT Init_libdatadog_api(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");

  crashtracker_init(profiling_module);
}

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
  VALUE ld_library_path = rb_hash_fetch(options, ID2SYM(rb_intern("ld_library_path")));
  VALUE tags_as_array = rb_hash_fetch(options, ID2SYM(rb_intern("tags_as_array")));
  VALUE action = rb_hash_fetch(options, ID2SYM(rb_intern("action")));
  VALUE upload_timeout_seconds = rb_hash_fetch(options, ID2SYM(rb_intern("upload_timeout_seconds")));

  VALUE start_action = ID2SYM(rb_intern("start"));
  VALUE update_on_fork_action = ID2SYM(rb_intern("update_on_fork"));

  ENFORCE_TYPE(exporter_configuration, T_ARRAY);
  ENFORCE_TYPE(tags_as_array, T_ARRAY);
  ENFORCE_TYPE(path_to_crashtracking_receiver_binary, T_STRING);
  ENFORCE_TYPE(ld_library_path, T_STRING);
  ENFORCE_TYPE(action, T_SYMBOL);
  ENFORCE_TYPE(upload_timeout_seconds, T_FIXNUM);

  if (action != start_action && action != update_on_fork_action) rb_raise(rb_eArgError, "Unexpected action: %+"PRIsVALUE, action);

  VALUE version = datadog_gem_version();
  ddog_prof_Endpoint endpoint = endpoint_from(exporter_configuration);

  // Tags are heap-allocated, so after here we can't raise exceptions otherwise we'll leak this memory
  // Start of exception-free zone to prevent leaks {{
  ddog_Vec_Tag tags = convert_tags(tags_as_array);

  ddog_prof_CrashtrackerConfiguration config = {
    .additional_files = {},
    // The Ruby VM already uses an alt stack to detect stack overflows so the crash handler must not overwrite it.
    //
    // @ivoanjo: Specifically, with `create_alt_stack = true` I saw a segfault, such as Ruby 2.6's bug with
    // "Process.detach(fork { exit! }).instance_variable_get(:@foo)" being turned into a
    // "-e:1:in `instance_variable_get': stack level too deep (SystemStackError)" by Ruby.
    //
    // The Ruby crash handler also seems to get confused when this option is enabled and
    // "Process.kill('SEGV', Process.pid)" gets run.
    .create_alt_stack = false,
    .endpoint = endpoint,
    .resolve_frames = DDOG_PROF_STACKTRACE_COLLECTION_ENABLED_WITH_SYMBOLS_IN_RECEIVER,
    .timeout_secs = FIX2INT(upload_timeout_seconds),
    // Waits for crash tracker to finish reporting the issue before letting the Ruby process die; see
    // https://github.com/DataDog/libdatadog/pull/477 for details
    .wait_for_receiver = true,
  };

  ddog_prof_CrashtrackerMetadata metadata = {
    .profiling_library_name = DDOG_CHARSLICE_C("dd-trace-rb"),
    .profiling_library_version = char_slice_from_ruby_string(version),
    .family = DDOG_CHARSLICE_C("ruby"),
    .tags = &tags,
  };

  ddog_prof_EnvVar ld_library_path_env = {
    .key = DDOG_CHARSLICE_C("LD_LIBRARY_PATH"),
    .val = char_slice_from_ruby_string(ld_library_path),
  };

  ddog_prof_CrashtrackerReceiverConfig receiver_config = {
    .args = {},
    .env = {.ptr = &ld_library_path_env, .len = 1},
    .path_to_receiver_binary = char_slice_from_ruby_string(path_to_crashtracking_receiver_binary),
    .optional_stderr_filename = {},
    .optional_stdout_filename = {},
  };

  ddog_prof_CrashtrackerResult result =
    action == start_action ?
      ddog_prof_Crashtracker_init_with_receiver(config, receiver_config, metadata) :
      ddog_prof_Crashtracker_update_on_fork(config, receiver_config, metadata);

  // Clean up before potentially raising any exceptions
  ddog_Vec_Tag_drop(tags);
  // }} End of exception-free zone to prevent leaks

  if (result.tag == DDOG_PROF_CRASHTRACKER_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to start/update the crash tracker: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}

static VALUE _native_stop(DDTRACE_UNUSED VALUE _self) {
  ddog_prof_CrashtrackerResult result = ddog_prof_Crashtracker_shutdown();

  if (result.tag == DDOG_PROF_CRASHTRACKER_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to stop the crash tracker: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}
