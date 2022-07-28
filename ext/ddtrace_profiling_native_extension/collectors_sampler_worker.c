#include <ruby.h>
#include "helpers.h"

static VALUE _native_sampling_loop(VALUE self, VALUE instance);

void collectors_sampler_worker_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_sampler_worker_class = rb_define_class_under(collectors_module, "SamplerWorker", rb_cObject);

  rb_define_singleton_method(collectors_sampler_worker_class, "_native_sampling_loop", _native_sampling_loop, 1);
}

static VALUE _native_sampling_loop(DDTRACE_UNUSED VALUE _self, VALUE instance) {
  fprintf(stderr, "Started native sampling loop\n");

  install_signal_handler();
  // install signal handler

  while (true /* FIXME: stopping criteria */) {
    // sleep
    // send signal for profiling
    // ???
  }
  return Qnil;
}

static void install_signal_handler() {
  struct sigaction our_signal_handler;
  struct sigaction old_signal_handler;

  sigemptyset(&our_signal_handler.sa_mask);
  our_signal_handler.sa_flags =
}


// signal handler
  // ensure GVL
  // enqueue sample for later

// sampler for later handler
  // ensure GVL (?)
  // handle exceptions
  // trigger cpu_and_wall_time collector
