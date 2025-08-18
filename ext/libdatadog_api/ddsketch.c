#include <ruby.h>

void ddsketch_init(VALUE datadog_module) {
  VALUE ddsketch_module = rb_define_module_under(datadog_module, "DDSketch");
}
