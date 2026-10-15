#pragma once

#include "buffer.h"

// Requires the main ractor's GVL, no GC in progress, and SIGPROF blocked against reentry.
bool miteruby_sample_event_publish(miteruby_buffer_t *buffer);
