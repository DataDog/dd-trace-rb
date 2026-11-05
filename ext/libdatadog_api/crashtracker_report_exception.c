#include <datadog/common.h>
#include <datadog/crashtracker.h>
#include <ruby.h>

#include "datadog_ruby_common.h"

static VALUE _native_report_ruby_exception(VALUE _self, VALUE exception_type,
                                          VALUE message, VALUE frames_data);

static bool process_crash_frames(VALUE frames_data, ddog_crasht_Handle_StackTrace *stack_trace);

void crashtracker_report_exception_init(VALUE crashtracker_class) {
  rb_define_singleton_method(crashtracker_class, "_native_report_ruby_exception",
                            _native_report_ruby_exception, 3);
}

static VALUE _native_report_ruby_exception(DDTRACE_UNUSED VALUE _self, VALUE exception_type,
                                          VALUE message, VALUE frames_data) {
  ENFORCE_TYPE(exception_type, T_STRING);
  ENFORCE_TYPE(message, T_STRING);
  ENFORCE_TYPE(frames_data, T_ARRAY);

  // Build stack trace
  ddog_crasht_StackTrace_NewResult stack_result = ddog_crasht_StackTrace_new();
  if (stack_result.tag != DDOG_CRASHT_STACK_TRACE_NEW_RESULT_OK) {
    ddog_Error_drop(&stack_result.err);
    return Qfalse;
  }

  ddog_crasht_Handle_StackTrace *stack_trace = &stack_result.ok;

  bool frames_ok = process_crash_frames(frames_data, stack_trace);
  if (frames_ok) {
    ddog_VoidResult complete_result = ddog_crasht_StackTrace_set_complete(stack_trace);
    if (complete_result.tag != DDOG_VOID_RESULT_OK) {
      ddog_crasht_StackTrace_drop(stack_trace);
      ddog_Error_drop(&complete_result.err);
      return Qfalse;
    }
  }

  // ddog_crasht_report_unhandled_exception takes ownership of stack_trace
  ddog_VoidResult result = ddog_crasht_report_unhandled_exception(
    char_slice_from_ruby_string(exception_type),
    char_slice_from_ruby_string(message),
    stack_trace
  );

  if (result.tag != DDOG_VOID_RESULT_OK) {
    ddog_Error_drop(&result.err);
    return Qfalse;
  }

  return Qtrue;
}

static bool process_crash_frames(VALUE frames_data, ddog_crasht_Handle_StackTrace *stack_trace) {
  size_t frame_count = RARRAY_LEN(frames_data);

  // Return false and early so we can mark the stack as incomplete
  // libdatadog's definition of an incomplete stack is that it has no frames
  // or that report generation died in the middle of unwinding frames
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
      ddog_Error_drop(&frame_result.err);
      return false;
    }

    ddog_crasht_Handle_StackFrame *frame = &frame_result.ok;

    ddog_VoidResult file_result = ddog_crasht_StackFrame_with_file(frame, char_slice_from_ruby_string(file_val));
    if (file_result.tag != DDOG_VOID_RESULT_OK) {
      ddog_crasht_StackFrame_drop(frame);
      ddog_Error_drop(&file_result.err);
      return false;
    }
    ddog_VoidResult func_result = ddog_crasht_StackFrame_with_function(frame, char_slice_from_ruby_string(func_val));
    if (func_result.tag != DDOG_VOID_RESULT_OK) {
      ddog_crasht_StackFrame_drop(frame);
      ddog_Error_drop(&func_result.err);
      return false;
    }

    uint32_t line = (uint32_t)FIX2INT(line_val);
    if (line > 0) {
      ddog_VoidResult line_result = ddog_crasht_StackFrame_with_line(frame, line);
      if (line_result.tag != DDOG_VOID_RESULT_OK) {
        ddog_crasht_StackFrame_drop(frame);
        ddog_Error_drop(&line_result.err);
        return false;
      }
    }

    ddog_VoidResult push_result = ddog_crasht_StackTrace_push_frame(stack_trace, frame, true);
    if (push_result.tag != DDOG_VOID_RESULT_OK) {
      ddog_crasht_StackFrame_drop(frame);
      ddog_Error_drop(&push_result.err);
      return false;
    }
  }

  return true;
}
