#pragma once

#include <ruby.h>

#include "buffer.h"
#include "../private_vm_api_access.h"

// ALL miteruby_sample_event_publish_* events MUST have the main ractor's GVL and no GC in progress. That's because
// we're about to grab Ruby VALUEs on the stack and we must tell the GC about them.
// (Aka, if you did that from another thread, we might grab things that the GC would later move or discard. Same
// if we're in the middle of GC: the GC might move the things we're grabbing, and perhaps our dmark was already called
// for this GC cycle so it won't get called again and won't see the new references).

// SIGPROF must already be blocked so another sampling signal cannot interrupt this call.
// Our signal handler runs with SIGPROF blocked automatically; simulated delivery blocks it explicitly.
bool miteruby_sample_event_publish_sighandler(miteruby_buffer_t *buffer);

// The non-signal-handler entry points require a non-NULL signal_mask including the producer signals.
bool miteruby_sample_event_publish_mask(miteruby_buffer_t *buffer, const sigset_t *signal_mask);
bool miteruby_sample_event_publish_thread(miteruby_buffer_t *buffer, value_thread_t thread, const sigset_t *signal_mask);

// For tests requiring deterministic CPU readings, including unavailable readings.
bool miteruby_sample_event_publish_testing(miteruby_buffer_t *buffer, value_thread_t thread, const sigset_t *signal_mask, cpu_time_t cpu_time);
