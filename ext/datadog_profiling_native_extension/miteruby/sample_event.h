#pragma once

#include <ruby.h>

#include "buffer.h"

// Both entry points require the main ractor's GVL and no GC in progress.
// SIGPROF must already be blocked so another sampling signal cannot interrupt this call.
// Our signal handler runs with SIGPROF blocked automatically; simulated delivery blocks it explicitly.
bool miteruby_sample_event_publish_sighandler(miteruby_buffer_t *buffer);

// signal_mask must be non-NULL and include the producer signals.
bool miteruby_sample_event_publish_mask(miteruby_buffer_t *buffer, VALUE thread, const sigset_t *signal_mask);
