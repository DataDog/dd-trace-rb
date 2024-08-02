#include <ruby.h>
#include "datadog_ruby_common.h"

void crashtracker_init(VALUE profiling_module);

void DDTRACE_EXPORT Init_libdatadog_api(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");

  crashtracker_init(profiling_module);
}
