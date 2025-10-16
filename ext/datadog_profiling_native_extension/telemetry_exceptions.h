#pragma once

#include <ruby.h>

// Global variables to hold references to the TelemetryAware exception classes
// These will be initialized when init_telemetry_exceptions() is called
VALUE telemetry_runtime_error_class = Qnil;
VALUE telemetry_argument_error_class = Qnil;
VALUE telemetry_type_error_class = Qnil;

// Initialize the telemetry exception classes
// Call this from your extension's Init_ function
static void init_telemetry_exceptions(void) {
    // Only initialize once
    if (telemetry_runtime_error_class != Qnil) return;
    
    // Get references to the Datadog::Core module and exception classes
    VALUE datadog_module = rb_const_get(rb_cObject, rb_intern("Datadog"));
    VALUE core_module = rb_const_get(datadog_module, rb_intern("Core"));
    
    telemetry_runtime_error_class = rb_const_get(core_module, rb_intern("TelemetryRuntimeError"));
    telemetry_argument_error_class = rb_const_get(core_module, rb_intern("TelemetryArgumentError"));
    telemetry_type_error_class = rb_const_get(core_module, rb_intern("TelemetryTypeError"));
    
    // Mark these as global references so they don't get garbage collected
    rb_global_variable(&telemetry_runtime_error_class);
    rb_global_variable(&telemetry_argument_error_class);
    rb_global_variable(&telemetry_type_error_class);
}

// Base macro to raise a telemetry-aware exception with both full message and safe telemetry description
#define TELEMETRY_RAISE(exception_class, safe_message, full_message_fmt, ...) \
    do { \
        if (exception_class == Qnil) init_telemetry_exceptions(); \
        VALUE args[2]; \
        args[0] = rb_sprintf(full_message_fmt, ##__VA_ARGS__); \
        args[1] = rb_str_new_cstr(safe_message); \
        rb_exc_raise(rb_class_new_instance(2, args, exception_class)); \
    } while (0)

// Function-like macros that look like standard C calls
// These provide a more natural call site that resembles rb_raise(rb_eRuntimeError, ...)

// Raise a TelemetryRuntimeError - looks like rb_raise(rb_eRuntimeError, ...)
#define raise_runtime_error(safe_message, full_message_fmt, ...) \
    TELEMETRY_RAISE(telemetry_runtime_error_class, safe_message, full_message_fmt, ##__VA_ARGS__)

// Raise a TelemetryArgumentError - looks like rb_raise(rb_eArgError, ...)
#define raise_argument_error(safe_message, full_message_fmt, ...) \
    TELEMETRY_RAISE(telemetry_argument_error_class, safe_message, full_message_fmt, ##__VA_ARGS__)

// Raise a TelemetryTypeError - looks like rb_raise(rb_eTypeError, ...)
#define raise_type_error(safe_message, full_message_fmt, ...) \
    TELEMETRY_RAISE(telemetry_type_error_class, safe_message, full_message_fmt, ##__VA_ARGS__)

// Legacy macro names for backward compatibility
#define TELEMETRY_RUNTIME_ERROR(safe_message, full_message_fmt, ...) \
    raise_runtime_error(safe_message, full_message_fmt, ##__VA_ARGS__)

#define TELEMETRY_ARGUMENT_ERROR(safe_message, full_message_fmt, ...) \
    raise_argument_error(safe_message, full_message_fmt, ##__VA_ARGS__)

#define TELEMETRY_TYPE_ERROR(safe_message, full_message_fmt, ...) \
    raise_type_error(safe_message, full_message_fmt, ##__VA_ARGS__)

// Helper macro to create delayed errors that can be raised asynchronously
#define CREATE_DELAYED_TELEMETRY_ERROR(state, safe_description, error_message_fmt, ...) \
    do { \
        if (telemetry_runtime_error_class == Qnil) init_telemetry_exceptions(); \
        VALUE args[2]; \
        args[0] = rb_sprintf(error_message_fmt, ##__VA_ARGS__); \
        args[1] = rb_str_new_cstr(safe_description); \
        state->failure_exception = rb_class_new_instance(2, args, telemetry_runtime_error_class); \
    } while (0)

// Example usage patterns that resemble standard rb_raise calls:
//
// OLD CODE:
//   rb_raise(rb_eRuntimeError, "Could not start CpuAndWallTimeWorker: There's already another instance active in thread %s", thread_id);
//
// NEW CODE (function-like style):
//   raise_runtime_error("Profiler instance conflict", 
//       "Could not start CpuAndWallTimeWorker: There's already another instance active in thread %s", thread_id);
//
// OLD CODE:
//   rb_raise(rb_eArgError, "GVL profiling is not supported in this Ruby version");
//
// NEW CODE (function-like style):
//   raise_argument_error("GVL profiling not supported", 
//       "GVL profiling is not supported in this Ruby version");
//
// OLD CODE:
//   rb_raise(rb_eTypeError, "Expected a string, got %s", rb_obj_classname(obj));
//
// NEW CODE (function-like style):
//   raise_type_error("Type validation failed", 
//       "Expected a string, got %s", rb_obj_classname(obj));