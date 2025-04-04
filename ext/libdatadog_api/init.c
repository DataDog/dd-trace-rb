#include <ruby.h>

#include "datadog_ruby_common.h"
#include "crashtracker.h"
#include "process_discovery.h"

// Used to report Ruby VM crashes.
// Once initialized, segfaults will be reported automatically using libdatadog.

void DDTRACE_EXPORT Init_libdatadog_api(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE core_module = rb_define_module_under(datadog_module, "Core");
  VALUE crashtracking_module = rb_define_module_under(core_module, "Crashtracking");
  VALUE process_discovery_module = rb_define_module_under(core_module, "ProcessDiscovery");

  crashtracker_init(crashtracking_module);
  process_discovery_init(process_discovery_module);
}
