#include <ruby.h>

#include "crashtracker.h"
#include "datadog_ruby_common.h"
#include "library_config.h"
#include "process_discovery.h"

void ddsketch_init(VALUE core_module);

void DDTRACE_EXPORT Init_libdatadog_api(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE core_module = rb_define_module_under(datadog_module, "Core");
  VALUE native_module = rb_define_module_under(core_module, "Native");

  // Initialize exception classes under Core::Native
  rb_global_variable(&eNativeRuntimeError);
  rb_global_variable(&eNativeArgumentError);
  rb_global_variable(&eNativeTypeError);
  eNativeRuntimeError = rb_define_class_under(native_module, "RuntimeError",
                                              rb_eRuntimeError);
  eNativeArgumentError = rb_define_class_under(
      native_module, "ArgumentError", rb_eArgError);
  eNativeTypeError = rb_define_class_under(native_module, "TypeError",
                                           rb_eTypeError);

  crashtracker_init(core_module);
  process_discovery_init(core_module);
  library_config_init(core_module);
  ddsketch_init(core_module);
}
