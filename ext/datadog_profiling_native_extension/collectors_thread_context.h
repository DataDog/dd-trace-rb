#pragma once

#include <ruby.h>
#include <stdbool.h>

void thread_context_collector_sample(
  VALUE self_instance,
  long current_monotonic_wall_time_ns,
  VALUE profiler_overhead_stack_thread
);
void thread_context_collector_sample_allocation(VALUE self_instance, unsigned int sample_weight, VALUE new_object);
void thread_context_collector_sample_skipped_allocation_samples(VALUE self_instance, unsigned int skipped_samples);
VALUE thread_context_collector_sample_after_gc(VALUE self_instance);
void thread_context_collector_on_gc_start(VALUE self_instance);
__attribute__((warn_unused_result)) bool thread_context_collector_on_gc_finish(VALUE self_instance);
VALUE enforce_thread_context_collector_instance(VALUE object);
void thread_context_collector_on_gvl_waiting(VALUE thread);
__attribute__((warn_unused_result)) bool thread_context_collector_on_gvl_running(VALUE thread);
VALUE thread_context_collector_sample_after_gvl_running(VALUE self_instance);
