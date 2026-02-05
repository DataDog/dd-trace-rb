#include <datadog/common.h>
#include <datadog/crashtracker.h>
#include <ruby.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>

#include "datadog_ruby_common.h"

// Pre-calculated static crash data
static struct {
  ddog_CharSlice library_name;
  ddog_CharSlice library_version;
  ddog_CharSlice family;
  ddog_crasht_ProcInfo proc_info;
  ddog_crasht_Handle_StackTrace *os_info_cache;
  bool initialized;
} static_crash_data = {
    .library_name = DDOG_CHARSLICE_C("dd-trace-rb"),
    .family = DDOG_CHARSLICE_C("ruby"),
    .initialized = false,
};

static VALUE
_native_report_ruby_exception(DDTRACE_UNUSED VALUE _self, VALUE agent_base_url,
                              VALUE exception_class, VALUE exception_message,
                              VALUE backtrace_locations, VALUE tags_as_array);
static void initialize_static_crash_data(void);
static VALUE _native_update_crash_data_on_fork(DDTRACE_UNUSED VALUE _self);

void ruby_crash_reporting_init(VALUE crashtracking_module) {
  VALUE crashtracker_class =
      rb_const_get(crashtracking_module, rb_intern("Component"));

  rb_define_singleton_method(crashtracker_class,
                             "_native_report_ruby_exception",
                             _native_report_ruby_exception, 5);
  rb_define_singleton_method(crashtracker_class,
                             "_native_update_crash_data_on_fork",
                             _native_update_crash_data_on_fork, 0);

  // Initialize static crash data once
  initialize_static_crash_data();
}

static void initialize_static_crash_data(void) {
  if (static_crash_data.initialized) {
    return;
  }

  // Pre-calculate library version
  VALUE version = datadog_gem_version();
  static_crash_data.library_version = char_slice_from_ruby_string(version);

  // Pre-calculate process info
  static_crash_data.proc_info.pid = (uint32_t)getpid();

  static_crash_data.initialized = true;
}

static VALUE
_native_report_ruby_exception(DDTRACE_UNUSED VALUE _self, VALUE agent_base_url,
                              VALUE exception_class, VALUE exception_message,
                              VALUE backtrace_locations, VALUE tags_as_array) {
  ENFORCE_TYPE(agent_base_url, T_STRING);
  ENFORCE_TYPE(exception_class, T_STRING);
  ENFORCE_TYPE(exception_message, T_STRING);
  ENFORCE_TYPE(backtrace_locations, T_ARRAY);
  ENFORCE_TYPE(tags_as_array, T_ARRAY);

  // exception free zone {{
  ddog_Endpoint *endpoint =
      ddog_endpoint_from_url(char_slice_from_ruby_string(agent_base_url));
  if (endpoint == NULL) {
    return Qtrue;
  }

  ddog_Vec_Tag tags = convert_tags(tags_as_array);

  // builder
  ddog_crasht_CrashInfoBuilder_NewResult builder_result =
      ddog_crasht_CrashInfoBuilder_new();
  if (builder_result.tag != DDOG_CRASHT_CRASH_INFO_BUILDER_NEW_RESULT_OK) {
    ddog_endpoint_drop(endpoint);
    ddog_Vec_Tag_drop(tags);
    // NEVER throw during crash reporting - just return silently
    return Qtrue;
  }

  ddog_crasht_Handle_CrashInfoBuilder *builder = &builder_result.ok;

  // metadata
  ddog_crasht_Metadata metadata = {
      .library_name = static_crash_data.library_name,
      .library_version = static_crash_data.library_version,
      .family = static_crash_data.family,
      .tags = &tags,
  };

  ddog_VoidResult result;

  // metadata
  result = ddog_crasht_CrashInfoBuilder_with_metadata(builder, metadata);
  if (result.tag != DDOG_VOID_RESULT_OK)
    goto cleanup;

  // error kind
  result = ddog_crasht_CrashInfoBuilder_with_kind(
      builder, DDOG_CRASHT_ERROR_KIND_UNHANDLED_EXCEPTION);
  if (result.tag != DDOG_VOID_RESULT_OK)
    goto cleanup;

  // timestamp
  result = ddog_crasht_CrashInfoBuilder_with_timestamp_now(builder);
  if (result.tag != DDOG_VOID_RESULT_OK)
    goto cleanup;

  // proc_info
  result = ddog_crasht_CrashInfoBuilder_with_proc_info(
      builder, static_crash_data.proc_info);
  if (result.tag != DDOG_VOID_RESULT_OK)
    goto cleanup;

  // os_info
  result = ddog_crasht_CrashInfoBuilder_with_os_info_this_machine(builder);
  if (result.tag != DDOG_VOID_RESULT_OK)
    goto cleanup;

  VALUE full_message = rb_sprintf("Unhandled %" PRIsVALUE ": %" PRIsVALUE,
                                  exception_class, exception_message);
  result = ddog_crasht_CrashInfoBuilder_with_message(
      builder, char_slice_from_ruby_string(full_message));
  if (result.tag != DDOG_VOID_RESULT_OK)
    goto cleanup;

  ddog_crasht_StackTrace_NewResult stack_result = ddog_crasht_StackTrace_new();
  if (stack_result.tag != DDOG_CRASHT_STACK_TRACE_NEW_RESULT_OK)
    goto cleanup;

  ddog_crasht_Handle_StackTrace *stack_trace = &stack_result.ok;

  long location_count = RARRAY_LEN(backtrace_locations);
  for (long i = 0; i < location_count; i++) {
    VALUE location = RARRAY_AREF(backtrace_locations, i);

    VALUE file_val = rb_funcall(location, rb_intern("path"), 0);
    VALUE line_val = rb_funcall(location, rb_intern("lineno"), 0);
    VALUE func_val = rb_funcall(location, rb_intern("label"), 0);

    if (NIL_P(file_val)) file_val = rb_str_new_cstr("<unknown>");
    if (NIL_P(func_val)) func_val = rb_str_new_cstr("<unknown>");

    ddog_crasht_StackFrame_NewResult frame_result = ddog_crasht_StackFrame_new();
    if (frame_result.tag == DDOG_CRASHT_STACK_FRAME_NEW_RESULT_OK) {
      ddog_crasht_Handle_StackFrame *frame = &frame_result.ok;

      if (RB_TYPE_P(file_val, T_STRING)) {
        result = ddog_crasht_StackFrame_with_file(frame, char_slice_from_ruby_string(file_val));
        if (result.tag != DDOG_VOID_RESULT_OK)
          continue; // skip frame on error
      }

      if (RB_TYPE_P(func_val, T_STRING)) {
        result = ddog_crasht_StackFrame_with_function(frame, char_slice_from_ruby_string(func_val));
        if (result.tag != DDOG_VOID_RESULT_OK)
          continue;
      }

      if (RB_TYPE_P(line_val, T_FIXNUM)) {
        uint32_t line_num = (uint32_t)FIX2INT(line_val);
        result = ddog_crasht_StackFrame_with_line(frame, line_num);
        if (result.tag != DDOG_VOID_RESULT_OK)
          continue;
      }

      result = ddog_crasht_StackTrace_push_frame(stack_trace, frame, true);
      if (result.tag != DDOG_VOID_RESULT_OK)
        continue;
    }
  }

  // mark stack trace as complete
  result = ddog_crasht_StackTrace_set_complete(stack_trace);
  if (result.tag != DDOG_VOID_RESULT_OK)
    goto cleanup;

  // add stack trace to crash info
  result = ddog_crasht_CrashInfoBuilder_with_stack(builder, stack_trace);
  if (result.tag != DDOG_VOID_RESULT_OK)
    goto cleanup;

  // Build the crash info
  ddog_crasht_CrashInfo_NewResult crash_info_result =
      ddog_crasht_CrashInfoBuilder_build(builder);
  if (crash_info_result.tag !=
      DDOG_CRASHT_RESULT_HANDLE_CRASH_INFO_OK_HANDLE_CRASH_INFO)
    goto cleanup;

  ddog_crasht_Handle_CrashInfo *crash_info = &crash_info_result.ok;

  // Upload to endpoint
  result = ddog_crasht_CrashInfo_upload_to_endpoint(crash_info, endpoint);

  // cleanup crash info
  ddog_crasht_CrashInfo_drop(crash_info);

cleanup:
  // clean up before potentially raising any exceptions
  ddog_crasht_CrashInfoBuilder_drop(builder);
  ddog_Vec_Tag_drop(tags);
  ddog_endpoint_drop(endpoint);
  // }} End of exception free zone
  return Qtrue;
}

// update pid
static VALUE _native_update_crash_data_on_fork(DDTRACE_UNUSED VALUE _self) {
  static_crash_data.proc_info.pid = (uint32_t)getpid();
  return Qtrue;
}
