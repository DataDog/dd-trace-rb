#pragma once

#include <ruby.h>

VALUE cpu_and_wall_time_collector_sample(VALUE self_instance);
VALUE cpu_and_wall_time_collector_sample_after_gc(VALUE self_instance);
VALUE cpu_and_wall_time_collector_on_gc_start(VALUE self_instance);
VALUE cpu_and_wall_time_collector_on_gc_finish(VALUE self_instance);
VALUE enforce_cpu_and_wall_time_collector_instance(VALUE object);
