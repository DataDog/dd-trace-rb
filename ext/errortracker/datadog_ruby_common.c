#include "datadog_ruby_common.h"

// IMPORTANT: Currently this file is copy-pasted between extensions. Make sure to update all versions when doing any change!

void raise_unexpected_type(VALUE value, const char *value_name, const char *type_name, const char *file, int line, const char* function_name) {
  rb_exc_raise(
    rb_exc_new_str(
      rb_eTypeError,
      rb_sprintf("wrong argument %"PRIsVALUE" for '%s' (expected a %s) at %s:%d:in `%s'",
        rb_inspect(value),
        value_name,
        type_name,
        file,
        line,
        function_name
      )
    )
  );
}

VALUE datadog_gem_version(void) {
  VALUE ddtrace_module = rb_const_get(rb_cObject, rb_intern("Datadog"));
  ENFORCE_TYPE(ddtrace_module, T_MODULE);
  VALUE version_module = rb_const_get(ddtrace_module, rb_intern("VERSION"));
  ENFORCE_TYPE(version_module, T_MODULE);
  VALUE version_string = rb_const_get(version_module, rb_intern("STRING"));
  ENFORCE_TYPE(version_string, T_STRING);
  return version_string;
}

static VALUE log_failure_to_process_tag(VALUE err_details) {
  VALUE datadog_module = rb_const_get(rb_cObject, rb_intern("Datadog"));
  VALUE logger = rb_funcall(datadog_module, rb_intern("logger"), 0);

  return rb_funcall(logger, rb_intern("warn"), 1, rb_sprintf("Failed to convert tag: %"PRIsVALUE, err_details));
}