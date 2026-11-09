#pragma once

#include <ruby.h>

#include "raw_events_queue.h"
#include "../private_vm_api_access.h"

#define NAME verstable_mark_threads_set
#define KEY_TY VALUE
#define HEADER_MODE
#include "hashtable/verstable.h"

typedef struct {
  miteruby_event_frame_refs_t *entries;
  size_t count;
  size_t capacity;
} miteruby_mark_cme_iseq_array_t;

typedef struct {
  miteruby_cme_iseq_id_t cme_iseq_id;
  miteruby_event_frame_position_t position;
} miteruby_location_t;

typedef struct {
  miteruby_location_t *entries;
  size_t count;
  size_t capacity;
} miteruby_location_array_t;

_Static_assert(sizeof(miteruby_location_t) == 4, "miteruby_location_t must be 4 bytes");

void miteruby_consumer_init(miteruby_raw_events_queue_t *raw_events_queue);
void miteruby_consumer_reset(void);

// Requires the main ractor's GVL; snapshots under the consumer mutex before allocating Ruby objects.
void miteruby_consumer_stats(VALUE stats_as_hash);

// Requires the main ractor's GVL on entry and exclusive consumer access throughout the loop.
// Reads and copies without the GVL; Ruby interruption exits the loop and unblocks SIGPROF.
// Storage exhaustion raises after reacquiring the GVL.
void miteruby_consumer_consume_loop(miteruby_raw_events_queue_t *raw_events_queue);

// Requires the main ractor's GVL throughout; may allocate and raise while holding the consumer mutex.
void miteruby_consumer_prepare_serialize(VALUE streaming_serializer_instance);
