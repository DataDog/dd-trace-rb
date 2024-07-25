#include <ruby.h>

// Used to mark function arguments that are deliberately left unused
#ifdef __GNUC__
  #define DDTRACE_UNUSED  __attribute__((unused))
#else
  #define DDTRACE_UNUSED
#endif

#define DDTRACE_EXPORT __attribute__ ((visibility ("default")))

void crashtracker_init(VALUE profiling_module);

void DDTRACE_EXPORT Init_libdatadog_api(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");

  crashtracker_init(profiling_module);
}
