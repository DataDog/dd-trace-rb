#include "allocator.h"
#include "raw_events_queue_marking.h"
#include "consumer_recorder.h"
#include "consumer.h"
#include "libdatadog_recorder.h"
#include "streaming_serializer.h"
#include "stack_dedup.h"
#include "compressed_deltas.h"

#include "../datadog_ruby_common.h"
#include "../helpers.h"
#include "../setup_signal_handler.h"
#include "../time_helpers.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <ruby/thread.h>
#include <threads.h>

#define MARK_THREADS_MAX_SIZE KiB_AS_BYTES(100)
#define MARK_CME_ISEQ_MAX_SIZE MiB_AS_BYTES(16)
#define MARK_CME_ISEQ_ARRAY_CAPACITY UINT16_MAX
#define LOCATION_MAP_MAX_SIZE MiB_AS_BYTES(16)

typedef struct {
  miteruby_event_frame_refs_t *entries;
  size_t count;
  size_t capacity;
} miteruby_mark_cme_iseq_array_t;

typedef struct {
  miteruby_cme_iseq_id_t cme_iseq_id;
  miteruby_event_frame_position_t position;
} miteruby_location_key_t;

typedef struct {
  miteruby_location_id_t location_id;
  const rb_iseq_t *iseq; // TODO: I think this will be useful for serialization, keep an eye out to remove it if doesn't end up being needed.
} miteruby_location_value_t;

static void *mark_threads_calloc(size_t size);
static void *mark_cme_iseq_calloc(size_t size);
static uint64_t cme_iseq_hash(miteruby_cme_iseq_id_t id, const miteruby_mark_cme_iseq_array_t *array);
static bool cme_iseq_equal(miteruby_cme_iseq_id_t left, miteruby_cme_iseq_id_t right, const miteruby_mark_cme_iseq_array_t *array);
static void *location_calloc(size_t size);
static uint64_t location_hash(miteruby_location_key_t key);
static bool location_equal(miteruby_location_key_t left, miteruby_location_key_t right);

#define NAME verstable_mark_threads_set
#define KEY_TY VALUE
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#define MALLOC_FN mark_threads_calloc
#define FREE_FN miteruby_allocator_free_sized
#include "hashtable/verstable.h"

#define NAME verstable_mark_cme_iseq_set
#define KEY_TY miteruby_cme_iseq_id_t
#define CTX_TY miteruby_mark_cme_iseq_array_t *
// Tiny hack: rely on Verstable's internal parameter name `table` to pass per-table context to hash/equality
// without changing Verstable
#define HASH_FN(key) cme_iseq_hash((key), table->ctx)
#define CMPR_FN(left, right) cme_iseq_equal((left), (right), table->ctx)
#define MALLOC_FN(size, ctx) mark_cme_iseq_calloc(size)
#define FREE_FN(ptr, size, ctx) miteruby_allocator_free_sized((ptr), (size))
#include "hashtable/verstable.h"

#define NAME verstable_location_map
#define KEY_TY miteruby_location_key_t
#define VAL_TY miteruby_location_value_t
#define HASH_FN location_hash
#define CMPR_FN location_equal
#define MALLOC_FN location_calloc
#define FREE_FN miteruby_allocator_free_sized
#include "hashtable/verstable.h"

#define INTERNED_EVENTS_QUEUE_MAX_SIZE MiB_AS_BYTES(16)

typedef struct {
  miteruby_raw_events_queue_t *raw_events_queue;
  verstable_mark_threads_set mark_threads_set;
  verstable_mark_cme_iseq_set mark_cme_iseq_set;
  miteruby_mark_cme_iseq_array_t mark_cme_iseq_array;
  verstable_location_map location_map;

  // MUST be Recursive because Ruby calls during serialization can re-enter marking and memory accounting. (Initialized with `mtx_recursive`)
  mtx_t mutex;

  uint8_t *interned_events_queue;
  size_t interned_events_pos;
  size_t interned_events_capacity;
} miteruby_consumer_state_t;

static miteruby_consumer_state_t consumer_state = {0};

typedef struct {
  miteruby_raw_events_queue_t *raw_events_queue;
  atomic_bool interrupted;
} consumer_consume_loop_args;

typedef enum {
  MITERUBY_CONSUMER_OK = 0,
  MITERUBY_CONSUMER_INTERRUPTED,
  MITERUBY_CONSUMER_END_OF_STREAM,
  MITERUBY_CONSUMER_RAW_EVENTS_QUEUE_INTERNAL_ERROR,
  MITERUBY_CONSUMER_DEDUP_STORAGE_FULL,
  MITERUBY_CONSUMER_INTERNED_EVENTS_QUEUE_FULL,
  MITERUBY_CONSUMER_MARK_THREADS_FULL,
  MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL,
  MITERUBY_CONSUMER_LOCATION_MAP_FULL,
  MITERUBY_CONSUMER_INVALID_FRAME,
} miteruby_consumer_exit_reason_t;

static VALUE consume_loop_body(VALUE args);
static VALUE consume_loop_ensure(VALUE args);
static void *consume_without_gvl(void *args);
static miteruby_consumer_exit_reason_t consume_without_gvl_internal(consumer_consume_loop_args *args);
static void consume_unblock(void *args);
static VALUE prepare_serialize_locked(VALUE args);
static VALUE prepare_serialize_unlock_ensure(VALUE unused);
static miteruby_consumer_exit_reason_t buffer_event(const miteruby_event_header_t *header);

static void *mark_threads_calloc(size_t size) {
  if (size > MARK_THREADS_MAX_SIZE) return NULL;
  return miteruby_allocator_alloc(size, "mark_threads");
}

static void *mark_cme_iseq_calloc(size_t size) {
  if (size > MARK_CME_ISEQ_MAX_SIZE) return NULL;
  return miteruby_allocator_alloc(size, "mark_cme_iseq");
}

static uint64_t cme_iseq_hash(miteruby_cme_iseq_id_t id, const miteruby_mark_cme_iseq_array_t *array) {
  return vt_wyhash(&array->entries[id.value], sizeof(miteruby_event_frame_refs_t));
}

static bool cme_iseq_equal(miteruby_cme_iseq_id_t left, miteruby_cme_iseq_id_t right, const miteruby_mark_cme_iseq_array_t *array) {
  miteruby_event_frame_refs_t left_refs = array->entries[left.value];
  miteruby_event_frame_refs_t right_refs = array->entries[right.value];
  return left_refs.cme == right_refs.cme && left_refs.iseq == right_refs.iseq;
}

static void *location_calloc(size_t size) {
  if (size > LOCATION_MAP_MAX_SIZE) return NULL;
  return miteruby_allocator_alloc(size, "location_map");
}

static uint64_t location_hash(miteruby_location_key_t key) {
  return vt_hash_integer(((uint32_t) key.cme_iseq_id.value << 16) | key.position.value);
}

static bool location_equal(miteruby_location_key_t left, miteruby_location_key_t right) {
  return left.cme_iseq_id.value == right.cme_iseq_id.value && left.position.value == right.position.value;
}

static void mutex_lock(mtx_t *mutex) {
  if (mtx_lock(mutex) != thrd_success) rb_bug("Failed to lock miteruby consumer mutex");
}

static void mutex_unlock(mtx_t *mutex) {
  if (mtx_unlock(mutex) != thrd_success) rb_bug("Failed to unlock miteruby consumer mutex");
}

static void consumer_mark(void *data) {
  miteruby_consumer_state_t *state = data;

  // We need to block the background consumer thread from consuming events so we have a consistent view...
  mutex_lock(&consumer_state.mutex);

  // ...and `miteruby_raw_events_queue_mark` marks while blocking production of any new events.
  //
  // (Holding the consumer mutex while blocking production is safe: publishers never acquire it, and queue marking
  // masks SIGPROF before taking the producer lock.)
  //
  // Every VALUE held by miteruby is protected by the queue, thread set, or frame-reference array; other buffers hold copies.
  miteruby_raw_events_queue_mark(state->raw_events_queue);

  // Use rb_gc_mark, not rb_gc_mark_movable: references held elsewhere are neither marked nor updated there,
  // so these objects must stay pinned at their current addresses.

  // Mark the verstable_mark_threads_set
  for (
    verstable_mark_threads_set_itr itr = verstable_mark_threads_set_first(&state->mark_threads_set);
    !verstable_mark_threads_set_is_end(itr);
    itr = verstable_mark_threads_set_next(itr)
  ) {
    rb_gc_mark(itr.data->key);
  }

  // Mark the mark_cme_iseq_array
  //
  // Note: Because `mark_cme_iseq_array` holds pairs of <cme, iseq>, we could be marking the same cme or iseq
  // more than once if it shows up in more than one pair. This is a bit of a classic space/time trade-off: we could
  // introduce another set just for marking, which would be less work at GC time but more memory for us to keep.
  // Something to keep in mind if Ruby's GC marking shows up as a hotspot?
  //
  // Note 2: While it would be tempting to consider marking only the cme when we know the iseq is the one the cme
  // points to, remember that we're marking **and pinning** so we really need to tell Ruby here to mark && pin both to
  // make sure Ruby doesn't move the iseq.
  //
  // Note 3: We temporarily place the pair we're looking up at entries[count], but only advance count when we
  // retain a new pair. A duplicate lookup or failed insertion can leave that slot populated, so we must exclude
  // it from marking: those references aren't owned by the array and, after a failed insertion, could become stale
  // once nothing else keeps them alive.
  const miteruby_mark_cme_iseq_array_t *array = &state->mark_cme_iseq_array;
  rb_gc_mark_locations((const VALUE *)array->entries, (const VALUE *)&array->entries[array->count]);

  mutex_unlock(&consumer_state.mutex);
}

static size_t consumer_size(const void *data) {
  const miteruby_consumer_state_t *state = data;

  mutex_lock(&consumer_state.mutex);

  size_t size = sizeof(*state) + sizeof(*state->raw_events_queue) +
    miteruby_allocator_alloc_size(state->interned_events_queue) +
    miteruby_allocator_alloc_size(state->mark_threads_set.buckets) +
    miteruby_allocator_alloc_size(state->mark_cme_iseq_set.buckets) +
    miteruby_allocator_alloc_size(state->mark_cme_iseq_array.entries) +
    miteruby_allocator_alloc_size(state->location_map.buckets) +
    miteruby_stack_dedup_size();

  mutex_unlock(&consumer_state.mutex);

  return size;
}

static const rb_data_type_t consumer_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::Consumer",
  .function = {
    .dmark = consumer_mark,
    .dfree = NULL, // TODO: The state has static storage and its wrapper is permanently rooted.
    .dsize = consumer_size,
  },
};

void miteruby_consumer_stats(VALUE stats_as_hash) {
  mutex_lock(&consumer_state.mutex);
  size_t interned_events_used_size = consumer_state.interned_events_pos;
  size_t mark_threads_entries = verstable_mark_threads_set_size(&consumer_state.mark_threads_set);
  size_t mark_cme_iseq_entries = consumer_state.mark_cme_iseq_array.count;
  size_t location_entries = verstable_location_map_size(&consumer_state.location_map);
  miteruby_stack_dedup_stats_t stack_dedup = miteruby_stack_dedup_stats();
  miteruby_consumer_recorder_stats_t recorder = miteruby_consumer_recorder_stats();
  mutex_unlock(&consumer_state.mutex);

  VALUE arguments[] = {
    ID2SYM(rb_intern("miteruby_raw_events_queue_max_size_bytes")), SIZET2NUM(MITERUBY_RAW_EVENTS_QUEUE_CAPACITY_BYTES),
    ID2SYM(rb_intern("miteruby_interned_events_queue_max_size_bytes")),
      SIZET2NUM(INTERNED_EVENTS_QUEUE_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_interned_events_queue_used_size_bytes")), SIZET2NUM(interned_events_used_size),
    ID2SYM(rb_intern("miteruby_mark_threads_max_size_bytes")), SIZET2NUM(MARK_THREADS_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_mark_threads_entries")), SIZET2NUM(mark_threads_entries),
    ID2SYM(rb_intern("miteruby_mark_cme_iseq_max_size_bytes")), SIZET2NUM(MARK_CME_ISEQ_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_mark_cme_iseq_entries")), SIZET2NUM(mark_cme_iseq_entries),
    ID2SYM(rb_intern("miteruby_location_map_max_size_bytes")), SIZET2NUM(LOCATION_MAP_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_location_map_entries")), SIZET2NUM(location_entries),
    ID2SYM(rb_intern("miteruby_unique_stacks_map_max_size_bytes")), SIZET2NUM(stack_dedup.map_max_size_bytes),
    ID2SYM(rb_intern("miteruby_unique_stacks_map_entries")), SIZET2NUM(stack_dedup.map_entries),
    ID2SYM(rb_intern("miteruby_thread_contexts_max_size_bytes")), SIZET2NUM(recorder.thread_contexts_max_size_bytes),
    ID2SYM(rb_intern("miteruby_thread_contexts_entries")), SIZET2NUM(recorder.thread_contexts_entries),
  };
  for (size_t i = 0; i < sizeof(arguments) / sizeof(*arguments); i += 2) rb_hash_aset(stats_as_hash, arguments[i], arguments[i + 1]);
}

void miteruby_consumer_init(miteruby_raw_events_queue_t *raw_events_queue) {
  if (mtx_init(&consumer_state.mutex, mtx_plain | mtx_recursive) != thrd_success)
    rb_raise(rb_eRuntimeError, "Failed to initialize miteruby.mutex");

  consumer_state.raw_events_queue = raw_events_queue;
  verstable_mark_threads_set_init(&consumer_state.mark_threads_set);
  verstable_mark_cme_iseq_set_init(&consumer_state.mark_cme_iseq_set, &consumer_state.mark_cme_iseq_array);
  verstable_location_map_init(&consumer_state.location_map);

  miteruby_stack_dedup_init();

  VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &consumer_typed_data, &consumer_state);

  // TODO: Let all this actually be garbage collected if it's not needed, now it's pinned forever
  rb_gc_register_mark_object(wrapper);
}

void miteruby_consumer_reset(void) {
  mutex_lock(&consumer_state.mutex);

  // Do this first so if we raise we don't leave weird intermediate state
  consumer_state.interned_events_pos = 0;
  miteruby_stack_dedup_reset();

  uint8_t *new_queue = miteruby_allocator_alloc(INTERNED_EVENTS_QUEUE_MAX_SIZE, "interned_events_queue");
  if (new_queue == NULL) {
    mutex_unlock(&consumer_state.mutex);
    rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.interned_events_queue");
  }

  miteruby_event_frame_refs_t *new_entries = miteruby_allocator_alloc(
    MARK_CME_ISEQ_ARRAY_CAPACITY * sizeof(*new_entries), "mark_cme_iseq_array"
  );
  if (new_entries == NULL) {
    miteruby_allocator_free(new_queue);
    mutex_unlock(&consumer_state.mutex);
    rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.mark_cme_iseq_array");
  }

  miteruby_allocator_free(consumer_state.interned_events_queue);
  consumer_state.interned_events_queue = new_queue;
  consumer_state.interned_events_capacity = INTERNED_EVENTS_QUEUE_MAX_SIZE;

  verstable_mark_threads_set_clear(&consumer_state.mark_threads_set);
  verstable_mark_cme_iseq_set_clear(&consumer_state.mark_cme_iseq_set);
  verstable_location_map_clear(&consumer_state.location_map);

  miteruby_allocator_free(consumer_state.mark_cme_iseq_array.entries);
  consumer_state.mark_cme_iseq_array = (miteruby_mark_cme_iseq_array_t) {
    .entries = new_entries,
    .count = 0,
    .capacity = MARK_CME_ISEQ_ARRAY_CAPACITY,
  };

  miteruby_consumer_recorder_init();

  mutex_unlock(&consumer_state.mutex);
}

void miteruby_consumer_consume_loop(miteruby_raw_events_queue_t *raw_events_queue) {
  consumer_consume_loop_args args = {
    .raw_events_queue = raw_events_queue,
  };
  atomic_init(&args.interrupted, false);
  rb_ensure(consume_loop_body, (VALUE) &args, consume_loop_ensure, Qnil);
}

static VALUE consume_loop_body(VALUE args_ptr) {
  consumer_consume_loop_args *args = (consumer_consume_loop_args *) args_ptr;

  miteruby_consumer_exit_reason_t reason = (miteruby_consumer_exit_reason_t) (uintptr_t)
    rb_thread_call_without_gvl(consume_without_gvl, args, consume_unblock, args);

  // TODO: Maybe in the future we want to more gracefully recover, e.g. maybe clear all the state and start accumulating again?
  if (reason == MITERUBY_CONSUMER_RAW_EVENTS_QUEUE_INTERNAL_ERROR) rb_raise(rb_eRuntimeError, "Miteruby raw events queue internal error");
  if (reason == MITERUBY_CONSUMER_DEDUP_STORAGE_FULL) rb_raise(rb_eRuntimeError, "Miteruby stack dedup storage is full");
  if (reason == MITERUBY_CONSUMER_INTERNED_EVENTS_QUEUE_FULL) rb_raise(rb_eRuntimeError, "Miteruby interned events queue is full");
  if (reason == MITERUBY_CONSUMER_MARK_THREADS_FULL) rb_raise(rb_eRuntimeError, "Miteruby mark_threads set is full");
  if (reason == MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL) rb_raise(rb_eRuntimeError, "Miteruby mark_cme_iseq storage is full");
  if (reason == MITERUBY_CONSUMER_LOCATION_MAP_FULL) rb_raise(rb_eRuntimeError, "Miteruby location map is full");

  if (reason == MITERUBY_CONSUMER_INVALID_FRAME) rb_raise(rb_eRuntimeError, "Miteruby invalid frame: both CME and ISEQ are NULL");

  return Qnil;
}

static void consume_unblock(void *args_ptr) {
  consumer_consume_loop_args *args = args_ptr;
  atomic_store(&args->interrupted, true);
  miteruby_raw_events_queue_wake_consumer(args->raw_events_queue);
}

static void *consume_without_gvl(void *args_ptr) {
  return (void *) (uintptr_t) consume_without_gvl_internal(args_ptr);
}

static miteruby_consumer_exit_reason_t consume_without_gvl_internal(consumer_consume_loop_args *args) {
  // TODO: We toggle this here directly as existing helper assumes GVL
  if (pthread_sigmask(SIG_BLOCK, &sigprof_signal_mask, NULL) != 0) rb_bug("Failed to block SIGPROF in miteruby consumer");

  for (;;) {
    miteruby_raw_events_queue_record_t record = miteruby_raw_events_queue_read(args->raw_events_queue, &args->interrupted);

    if (record.internal_error) return MITERUBY_CONSUMER_RAW_EVENTS_QUEUE_INTERNAL_ERROR;
    if (record.interrupted) return MITERUBY_CONSUMER_INTERRUPTED;
    if (record.end_of_stream) return MITERUBY_CONSUMER_END_OF_STREAM;
    if (record.data == NULL) continue;

    // The borrowed event stays in queue marking until the next read, after this transfer completes.
    mutex_lock(&consumer_state.mutex);
    miteruby_consumer_exit_reason_t reason = buffer_event((const miteruby_event_header_t *)record.data);
    mutex_unlock(&consumer_state.mutex);

    if (reason != MITERUBY_CONSUMER_OK) return reason;
  }
}

static VALUE consume_loop_ensure(DDTRACE_UNUSED VALUE unused) {
  unblock_sigprof_signal_handler_from_running_in_current_thread();
  return Qnil;
}

typedef struct {
  VALUE recorder_instance;
  VALUE streaming_serializer_instance;
} prepare_serialize_args;

void miteruby_consumer_prepare_serialize(VALUE recorder_instance, VALUE streaming_serializer_instance) {
  miteruby_libdatadog_recorder_enforce_available(recorder_instance);
  prepare_serialize_args args = {recorder_instance, streaming_serializer_instance};
  mutex_lock(&consumer_state.mutex);
  rb_ensure(prepare_serialize_locked, (VALUE) &args, prepare_serialize_unlock_ensure, Qnil);
  RB_GC_GUARD(recorder_instance);
  RB_GC_GUARD(streaming_serializer_instance);
}

static VALUE prepare_serialize_locked(VALUE args) {
  prepare_serialize_args *recorders = (prepare_serialize_args *) args;
  miteruby_streaming_serializer_prepare_serialize(
    recorders->streaming_serializer_instance, consumer_state.interned_events_queue, consumer_state.interned_events_pos
  );
  monotonic_to_system_epoch_state time_converter = MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER;

  for (size_t pos = 0; pos < consumer_state.interned_events_pos;) {
    const miteruby_event_deduped_sample_t *event = (const miteruby_event_deduped_sample_t *)(consumer_state.interned_events_queue + pos);
    miteruby_stack_t stack = miteruby_stack_dedup_get(consumer_state.interned_events_queue, event->stack_id);
    miteruby_consumer_record_stack_sample(recorders->recorder_instance, event, stack, &time_converter);
    pos += event->header.size_bytes;
  }

  consumer_state.interned_events_pos = 0;
  miteruby_stack_dedup_reset();

  return Qnil;
}

static VALUE prepare_serialize_unlock_ensure(DDTRACE_UNUSED VALUE unused) {
  mutex_unlock(&consumer_state.mutex);
  return Qnil;
}

static bool retain_thread(VALUE thread) {
  return !verstable_mark_threads_set_is_end(verstable_mark_threads_set_get_or_insert(&consumer_state.mark_threads_set, thread));
}

static miteruby_consumer_exit_reason_t retain_cme_iseq(miteruby_event_frame_refs_t refs, miteruby_cme_iseq_id_t *id) {
  if (refs.cme == NULL && refs.iseq == NULL) return MITERUBY_CONSUMER_INVALID_FRAME;

  miteruby_mark_cme_iseq_array_t *array = &consumer_state.mark_cme_iseq_array;
  if (array->count >= array->capacity) return MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL;

  // The set stores array indices, so its hash and equality functions need an index to find the cme/iseq pair.
  // Put the pair in the next unused slot so we can look it up using that slot's index. If the pair is already
  // in the set, we get its existing index back and can reuse this slot on the next lookup. Otherwise, the set
  // keeps the new index and we advance count to keep the pair in the array.
  array->entries[array->count] = refs;
  verstable_mark_cme_iseq_set_itr entry = verstable_mark_cme_iseq_set_get_or_insert(
    &consumer_state.mark_cme_iseq_set, (miteruby_cme_iseq_id_t) {.value = (uint16_t) array->count}
  );
  if (verstable_mark_cme_iseq_set_is_end(entry)) return MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL;
  *id = entry.data->key;
  if (id->value == array->count) array->count++;
  return MITERUBY_CONSUMER_OK;
}

miteruby_event_frame_refs_t miteruby_id_to_frame_refs(miteruby_cme_iseq_id_t id) {
  if (id.value >= consumer_state.mark_cme_iseq_array.count)
    rb_raise(rb_eRuntimeError, "Miteruby unknown CME/ISEQ ID: %u", (unsigned int) id.value);
  return consumer_state.mark_cme_iseq_array.entries[id.value];
}

// TODO: Temporary hack, until we have a better way of mapping ids to the data they represent at serialization time
miteruby_cme_iseq_id_t miteruby_hack_location_id_to_cme_seq_id(miteruby_location_id_t id, miteruby_event_frame_position_t *position) {
  for (
    verstable_location_map_itr entry = verstable_location_map_first(&consumer_state.location_map);
    !verstable_location_map_is_end(entry);
    entry = verstable_location_map_next(entry)
  ) {
    if (entry.data->val.location_id.value.value == id.value.value) {
      *position = entry.data->key.position;
      return entry.data->key.cme_iseq_id;
    }
  }
  rb_raise(rb_eRuntimeError, "Miteruby unknown location ID: %u", (unsigned int) id.value.value);
}

static miteruby_consumer_exit_reason_t intern_location(miteruby_location_key_t key, const rb_iseq_t *iseq, miteruby_location_id_t *id) {
  size_t next_id = verstable_location_map_size(&consumer_state.location_map);
  // We fail early if map is already at capacity
  if (next_id > UINT20_MAX) return MITERUBY_CONSUMER_LOCATION_MAP_FULL;

  verstable_location_map_itr entry = verstable_location_map_get_or_insert(
    &consumer_state.location_map, key, (miteruby_location_value_t) {
      .location_id = {.value = {.value = (unsigned int) next_id}},
      .iseq = iseq,
    }
  );
  if (verstable_location_map_is_end(entry)) return MITERUBY_CONSUMER_LOCATION_MAP_FULL;
  *id = entry.data->val.location_id;
  return MITERUBY_CONSUMER_OK;
}

static miteruby_consumer_exit_reason_t buffer_event(const miteruby_event_header_t *header) {
  // TODO: Handle overflow and other kinds of events
  if (header->type != MITERUBY_EVENT_STACK_SAMPLE) return MITERUBY_CONSUMER_OK;

  const miteruby_event_stack_sample_t *event = (const miteruby_event_stack_sample_t *)header;
  miteruby_stack_hash_t stack_hash = miteruby_stack_hash(event);
  miteruby_stack_dedup_result_t result = miteruby_stack_dedup_get_or_reserve(
    header->frame_count, stack_hash, consumer_state.interned_events_queue,
    consumer_state.interned_events_pos, consumer_state.interned_events_capacity
  );
  if (result.error_storage_full) return MITERUBY_CONSUMER_INTERNED_EVENTS_QUEUE_FULL;
  bool new_stack = result.ok.reserved;

  // Retain references before the next queue read releases the record's GC protection.
  if (!retain_thread(event->thread.value)) {
    return MITERUBY_CONSUMER_MARK_THREADS_FULL;
  }

  if (new_stack) {
    miteruby_stack_t stack = result.ok.stack;
    uint8_t *cursor = stack.ids;
    uint20_t previous_value = {0};
    const miteruby_event_frame_position_t *positions = (const miteruby_event_frame_position_t *)&event->refs[header->frame_count];
    for (uint16_t i = 0; i < header->frame_count; i++) {
      miteruby_cme_iseq_id_t cme_iseq_id;
      miteruby_consumer_exit_reason_t reason = retain_cme_iseq(event->refs[i], &cme_iseq_id);
      if (reason != MITERUBY_CONSUMER_OK) return reason;
      miteruby_location_id_t location_id;
      reason = intern_location(
        (miteruby_location_key_t) {.cme_iseq_id = cme_iseq_id, .position = positions[i]}, event->refs[i].iseq, &location_id
      );
      if (reason != MITERUBY_CONSUMER_OK) return reason;
      // As we turn the (cme_iseq_id, position), into an id, we write those ids into the deduped stack storage
      if (!miteruby_compressed_deltas_write(previous_value, location_id.value, &cursor, stack.end)) return MITERUBY_CONSUMER_DEDUP_STORAGE_FULL;
      previous_value = location_id.value;
    }
    if (!miteruby_stack_dedup_commit(consumer_state.interned_events_queue, result.ok.id, stack_hash, cursor)) return MITERUBY_CONSUMER_DEDUP_STORAGE_FULL;
  }

  miteruby_event_deduped_sample_t *deduped = (miteruby_event_deduped_sample_t *)(consumer_state.interned_events_queue + consumer_state.interned_events_pos);
  uint16_t size_bytes = deduped->header.size_bytes;
  deduped->header = *header;
  deduped->thread = event->thread;
  deduped->stack_id = result.ok.id;
  deduped->header.type = MITERUBY_EVENT_DEDUPED_SAMPLE;
  deduped->header.size_bytes = size_bytes;
  consumer_state.interned_events_pos += size_bytes;

  return MITERUBY_CONSUMER_OK;
}
