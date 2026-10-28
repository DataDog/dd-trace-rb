#pragma once

#include <ruby.h>

#include "buffer.h"

void miteruby_consumer_init(miteruby_buffer_t *buffer);
void miteruby_consumer_reset(void);

// Requires the main ractor's GVL; snapshots under the consumer mutex before allocating Ruby objects.
void miteruby_consumer_stats(VALUE stats_as_hash);

// Requires the main ractor's GVL on entry and exclusive consumer access throughout the loop.
// Reads and copies without the GVL; Ruby interruption exits the loop and unblocks SIGPROF.
// Storage exhaustion raises after reacquiring the GVL.
void miteruby_consumer_consume_loop(miteruby_buffer_t *buffer);

// Requires the main ractor's GVL throughout; may allocate and raise while holding the consumer mutex.
void miteruby_consumer_prepare_serialize(VALUE recorder_instance);
