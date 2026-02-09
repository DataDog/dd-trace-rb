#include <datadog/common.h>
#include <datadog/crashtracker.h>
#include <ruby.h>
#include <sys/types.h>
#include <unistd.h>
#include <string.h>

#include "datadog_ruby_common.h"

static VALUE _native_report_ruby_exception(VALUE _self, VALUE agent_base_url,
                                          VALUE message, VALUE frames_data,
                                          VALUE tags_as_array, VALUE library_version);

static bool process_crash_frames(VALUE frames_data, ddog_crasht_Handle_StackTrace *stack_trace);
static bool build_and_send_crash_report(ddog_crasht_Metadata metadata,
                                        ddog_Endpoint *endpoint,
                                        VALUE message,
                                        VALUE frames_data);

void crashtracker_report_exception_init(VALUE crashtracker_class) {
  rb_define_singleton_method(crashtracker_class, "_native_report_ruby_exception",
                            _native_report_ruby_exception, 5);
}

static VALUE _native_report_ruby_exception(DDTRACE_UNUSED VALUE _self, VALUE agent_base_url,
                                          VALUE message, VALUE frames_data,
                                          VALUE tags_as_array, VALUE library_version) {
  ENFORCE_TYPE(agent_base_url, T_STRING);
  ENFORCE_TYPE(message, T_STRING);
  ENFORCE_TYPE(frames_data, T_ARRAY);
  ENFORCE_TYPE(tags_as_array, T_ARRAY);
  ENFORCE_TYPE(library_version, T_STRING);

  ddog_Endpoint *endpoint = ddog_endpoint_from_url(char_slice_from_ruby_string(agent_base_url));
  if (!endpoint) return Qfalse;

  ddog_Vec_Tag tags = convert_tags(tags_as_array);

  ddog_crasht_Metadata metadata = {
    .library_name = DDOG_CHARSLICE_C("dd-trace-rb"),
    .library_version = char_slice_from_ruby_string(library_version),
    .family = DDOG_CHARSLICE_C("ruby"),
    .tags = &tags,
  };

  // Build and send report
  bool success = build_and_send_crash_report(metadata, endpoint, message, frames_data);
  ddog_Vec_Tag_drop(tags);
  ddog_endpoint_drop(endpoint);

  return success ? Qtrue : Qfalse;
}

static bool process_crash_frames(VALUE frames_data, ddog_crasht_Handle_StackTrace *stack_trace) {
  size_t frame_count = RARRAY_LEN(frames_data);

  // Return false and early so we can mark the stack as incomplete
  // libdatadog's definition of an incomplete stack is that it has no frames
  if (frame_count == 0) {
    return false;
  }

  for (size_t i = 0; i < frame_count; i++) {
    VALUE frame_array = RARRAY_AREF(frames_data, i);

    // ruby should guarantee [String, String, Integer]
    if (!RB_TYPE_P(frame_array, T_ARRAY) || RARRAY_LEN(frame_array) != 3) {
      // Malformed data from Ruby; this is a bug, bail out
      return false;
    }

    VALUE file_val = RARRAY_AREF(frame_array, 0);
    VALUE func_val = RARRAY_AREF(frame_array, 1);
    VALUE line_val = RARRAY_AREF(frame_array, 2);

    // validate types; Ruby should guarantee these
    if (!RB_TYPE_P(file_val, T_STRING) || !RB_TYPE_P(func_val, T_STRING) || !RB_TYPE_P(line_val, T_FIXNUM)) {
      // Type mismatch from Ruby; this is a bug, bail out
      return false;
    }

    ddog_crasht_StackFrame_NewResult frame_result = ddog_crasht_StackFrame_new();
    if (frame_result.tag != DDOG_CRASHT_STACK_FRAME_NEW_RESULT_OK) {
      return false;
    }

    ddog_crasht_Handle_StackFrame *frame = &frame_result.ok;

    if (ddog_crasht_StackFrame_with_file(frame, char_slice_from_ruby_string(file_val)).tag != DDOG_VOID_RESULT_OK) {
      ddog_crasht_StackFrame_drop(frame);
      return false;
    }
    if (ddog_crasht_StackFrame_with_function(frame, char_slice_from_ruby_string(func_val)).tag != DDOG_VOID_RESULT_OK) {
      ddog_crasht_StackFrame_drop(frame);
      return false;
    }

    uint32_t line = (uint32_t)FIX2INT(line_val);
    if (line > 0) {
      if (ddog_crasht_StackFrame_with_line(frame, line).tag != DDOG_VOID_RESULT_OK) {
        ddog_crasht_StackFrame_drop(frame);
        return false;
      }
    }

    if (ddog_crasht_StackTrace_push_frame(stack_trace, frame, true).tag != DDOG_VOID_RESULT_OK) {
      ddog_crasht_StackFrame_drop(frame);
      return false;
    }
  }

  return true;
}

static bool build_and_send_crash_report(ddog_crasht_Metadata metadata,
                                        ddog_Endpoint *endpoint,
                                        VALUE message,
                                        VALUE frames_data) {
  ddog_crasht_Handle_StackTrace *stack_trace = NULL;

  ddog_crasht_CrashInfoBuilder_NewResult builder_result = ddog_crasht_CrashInfoBuilder_new();
  if (builder_result.tag != DDOG_CRASHT_CRASH_INFO_BUILDER_NEW_RESULT_OK) {
    return false;
  }

  ddog_crasht_Handle_CrashInfoBuilder *builder = &builder_result.ok;

  // Setup builder metadata and configuration
  if (ddog_crasht_CrashInfoBuilder_with_metadata(builder, metadata).tag != DDOG_VOID_RESULT_OK) {
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  if (ddog_crasht_CrashInfoBuilder_with_kind(builder, DDOG_CRASHT_ERROR_KIND_UNHANDLED_EXCEPTION).tag != DDOG_VOID_RESULT_OK) {
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  // Send ping first
  if (ddog_crasht_CrashInfoBuilder_upload_ping_to_endpoint(builder, endpoint).tag != DDOG_VOID_RESULT_OK) {
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  ddog_crasht_ProcInfo proc_info = { .pid = (uint32_t)getpid() };
  if (ddog_crasht_CrashInfoBuilder_with_proc_info(builder, proc_info).tag != DDOG_VOID_RESULT_OK) {
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  if (ddog_crasht_CrashInfoBuilder_with_os_info_this_machine(builder).tag != DDOG_VOID_RESULT_OK) {
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  if (ddog_crasht_CrashInfoBuilder_with_message(builder, char_slice_from_ruby_string(message)).tag != DDOG_VOID_RESULT_OK) {
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  // Create and populate stack trace
  ddog_crasht_StackTrace_NewResult stack_result = ddog_crasht_StackTrace_new();
  if (stack_result.tag != DDOG_CRASHT_STACK_TRACE_NEW_RESULT_OK) {
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  stack_trace = &stack_result.ok;

  bool frames_processed_successfully = process_crash_frames(frames_data, stack_trace);

  // Only mark as complete if we successfully processed all frames
  if (frames_processed_successfully) {
    if (ddog_crasht_StackTrace_set_complete(stack_trace).tag != DDOG_VOID_RESULT_OK) {
      ddog_crasht_StackTrace_drop(stack_trace);
      ddog_crasht_CrashInfoBuilder_drop(builder);
      return false;
    }
  }
  // If frames processing failed, we still include the stack trace (which may be empty or partial)
  // but don't mark it as complete, indicating it's incomplete

  if (ddog_crasht_CrashInfoBuilder_with_stack(builder, stack_trace).tag != DDOG_VOID_RESULT_OK) {
    ddog_crasht_StackTrace_drop(stack_trace);
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  // Builder takes ownership of stack_trace, so we don't need to clean it up anymore
  stack_trace = NULL;

  // Build and upload crash info
  ddog_crasht_CrashInfo_NewResult crash_info_result = ddog_crasht_CrashInfoBuilder_build(builder);
  if (crash_info_result.tag != DDOG_CRASHT_RESULT_HANDLE_CRASH_INFO_OK_HANDLE_CRASH_INFO) {
    ddog_crasht_CrashInfoBuilder_drop(builder);
    return false;
  }

  ddog_crasht_Handle_CrashInfo *crash_info = &crash_info_result.ok;
  ddog_VoidResult upload_result = ddog_crasht_CrashInfo_upload_to_endpoint(crash_info, endpoint);
  bool success = (upload_result.tag == DDOG_VOID_RESULT_OK);

  ddog_crasht_CrashInfo_drop(crash_info);
  return success;
}
