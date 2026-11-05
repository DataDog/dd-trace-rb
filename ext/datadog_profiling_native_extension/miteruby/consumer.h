#pragma once

#include <ruby.h>

#include "raw_events_queue.h"
#include "../private_vm_api_access.h"

void miteruby_consumer_init(miteruby_raw_events_queue_t *raw_events_queue);
void miteruby_consumer_reset(void);

// Requires the main ractor's GVL; snapshots under the consumer mutex before allocating Ruby objects.
void miteruby_consumer_stats(VALUE stats_as_hash);

// Requires the main ractor's GVL on entry and exclusive consumer access throughout the loop.
// Reads and copies without the GVL; Ruby interruption exits the loop and unblocks SIGPROF.
// Storage exhaustion raises after reacquiring the GVL.
void miteruby_consumer_consume_loop(miteruby_raw_events_queue_t *raw_events_queue);

// Requires the main ractor's GVL throughout; may allocate and raise while holding the consumer mutex.
void miteruby_consumer_prepare_serialize(VALUE recorder_instance, VALUE streaming_serializer_instance);

// Caller holds the main ractor's GVL and consumer mutex; missing IDs raise an internal error.
miteruby_event_frame_refs_t miteruby_id_to_frame_refs(miteruby_cme_iseq_id_t id);
miteruby_cme_iseq_id_t miteruby_hack_location_id_to_cme_seq_id(miteruby_location_id_t id, miteruby_event_frame_position_t *position);
