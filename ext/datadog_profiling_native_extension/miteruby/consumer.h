#pragma once

#include <ruby.h>

#include "raw_events_queue.h"

void miteruby_consumer_init(miteruby_raw_events_queue_t *raw_events_queue);
void miteruby_consumer_reset(void);

// Requires the main ractor's GVL; snapshots under the consumer mutex before allocating Ruby objects.
void miteruby_consumer_stats(VALUE stats_as_hash);

// Requires the main ractor's GVL on entry and exclusive consumer access throughout the loop.
// Reads and copies without the GVL; Ruby interruption exits the loop and unblocks SIGPROF.
// Storage exhaustion raises after reacquiring the GVL.
void miteruby_consumer_consume_loop(miteruby_raw_events_queue_t *raw_events_queue);

// Requires the main ractor's GVL throughout; may allocate and raise while holding the consumer mutex.
void miteruby_consumer_prepare_serialize(VALUE recorder_instance);
