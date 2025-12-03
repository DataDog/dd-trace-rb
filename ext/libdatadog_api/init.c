#include <ruby.h>

#include "datadog_ruby_common.h"
#include "crashtracker.h"
#include "process_discovery.h"
#include "library_config.h"

void ddsketch_init(VALUE core_module);

void DDTRACE_EXPORT Init_libdatadog_api(void) {
  VALUE datadog_module = rb_define_module("Datadog");

  // MUST be called before all other initialization
  datadog_ruby_common_init(datadog_module);

  VALUE core_module = rb_define_module_under(datadog_module, "Core");

  crashtracker_init(core_module);
  process_discovery_init(core_module);
  library_config_init(core_module);
  ddsketch_init(core_module);
}
