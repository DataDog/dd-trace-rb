#include <ruby.h>
#include "datadog_ruby_common.h"

void crashtracker_init(VALUE crashtracking_module);
void di_init(VALUE di_module);

// Used to report Ruby VM crashes.
// Once initialized, segfaults will be reported automatically using libdatadog.

void DDTRACE_EXPORT Init_libdatadog_api(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE core_module = rb_define_module_under(datadog_module, "Core");
  VALUE crashtracking_module = rb_define_module_under(core_module, "Crashtracking");
  VALUE di_module = rb_define_module_under(datadog_module, "DI");

  crashtracker_init(crashtracking_module);
  di_init(di_module);
}
