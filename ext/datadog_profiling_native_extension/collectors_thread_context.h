#pragma once

#include <ruby.h>
#include <stdbool.h>

#include "gvl_profiling_helper.h"

void thread_context_collector_sample(
  VALUE self_instance,
  long current_monotonic_wall_time_ns,
  VALUE profiler_overhead_stack_thread
);
__attribute__((warn_unused_result)) bool thread_context_collector_prepare_sample_inside_signal_handler(VALUE self_instance);
void thread_context_collector_sample_allocation(VALUE self_instance, unsigned int sample_weight, VALUE new_object);
void thread_context_collector_sample_skipped_allocation_samples(VALUE self_instance, unsigned int skipped_samples);
VALUE thread_context_collector_sample_after_gc(VALUE self_instance);
void thread_context_collector_on_gc_start(VALUE self_instance);
__attribute__((warn_unused_result)) bool thread_context_collector_on_gc_finish(VALUE self_instance);
VALUE enforce_thread_context_collector_instance(VALUE object);

#ifdef USE_DEFERRED_HEAP_ALLOCATION_RECORDING
// Finalize any pending heap allocation recordings.
// On Ruby 4+, heap allocations are recorded in two phases: during on_newobj_event we capture
// the object reference, then later we safely call rb_obj_id() to get the object ID.
// Returns true on success, false if a fatal error occurred and heap profiling should be disabled.
bool thread_context_collector_finalize_heap_recordings(VALUE self_instance);

// Returns true if the pending heap recordings buffer is getting full and should be flushed soon.
bool thread_context_collector_heap_pending_buffer_pressure(VALUE self_instance);
#endif

#ifndef NO_GVL_INSTRUMENTATION
  typedef enum {
    ON_GVL_RUNNING_UNKNOWN, // Thread is not known, it may not even be from the current Ractor
    ON_GVL_RUNNING_DONT_SAMPLE, // Thread is known, but "Waiting for GVL" period was too small to be sampled
    ON_GVL_RUNNING_SAMPLE, // Thread is known, and "Waiting for GVL" period should be sampled
  } on_gvl_running_result;

  void thread_context_collector_on_gvl_waiting(gvl_profiling_thread thread);
  __attribute__((warn_unused_result)) on_gvl_running_result thread_context_collector_on_gvl_running(gvl_profiling_thread thread);
  VALUE thread_context_collector_sample_after_gvl_running(VALUE self_instance, VALUE current_thread, long current_monotonic_wall_time_ns);
#endif
