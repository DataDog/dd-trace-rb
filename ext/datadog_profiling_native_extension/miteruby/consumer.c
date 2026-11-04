#include "allocator.h"
#include "raw_events_queue_marking.h"
#include "consumer_recorder.h"
#include "consumer.h"
#include "libdatadog_recorder.h"
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
#define LOCATION_MAP_MAX_SIZE MiB_AS_BYTES(16)

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
static uint64_t cme_iseq_hash(miteruby_event_frame_refs_t refs);
static bool cme_iseq_equal(miteruby_event_frame_refs_t left, miteruby_event_frame_refs_t right);
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

#define NAME verstable_mark_cme_iseq_map
#define KEY_TY miteruby_event_frame_refs_t
#define VAL_TY miteruby_cme_iseq_id_t
#define HASH_FN cme_iseq_hash
#define CMPR_FN cme_iseq_equal
#define MALLOC_FN mark_cme_iseq_calloc
#define FREE_FN miteruby_allocator_free_sized
#include "hashtable/verstable.h"

#define NAME verstable_location_map
#define KEY_TY miteruby_location_key_t
#define VAL_TY miteruby_location_value_t
#define HASH_FN location_hash
#define CMPR_FN location_equal
#define MALLOC_FN location_calloc
#define FREE_FN miteruby_allocator_free_sized
#include "hashtable/verstable.h"

#define INTERNED_EVENTS_QUEUE_MAX_CAPACITY (MiB_AS_BYTES(16) / sizeof(miteruby_event_deduped_sample_t))

typedef struct {
  miteruby_raw_events_queue_t *raw_events_queue;
  verstable_mark_threads_set mark_threads_set;
  verstable_mark_cme_iseq_map mark_cme_iseq_map;
  verstable_location_map location_map;

  // MUST be Recursive because Ruby calls during serialization can re-enter marking and memory accounting. (Initialized with `mtx_recursive`)
  mtx_t mutex;

  miteruby_event_deduped_sample_t *interned_events_queue;
  size_t interned_events_count;
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
static VALUE prepare_serialize_locked(VALUE recorder_instance);
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

static uint64_t cme_iseq_hash(miteruby_event_frame_refs_t refs) {
  return vt_wyhash(&refs, sizeof(refs));
}

static bool cme_iseq_equal(miteruby_event_frame_refs_t left, miteruby_event_frame_refs_t right) {
  return left.cme == right.cme && left.iseq == right.iseq;
}

static void *location_calloc(size_t size) {
  if (size > LOCATION_MAP_MAX_SIZE) return NULL;
  return miteruby_allocator_alloc(size, "location_map");
}

static uint64_t location_hash(miteruby_location_key_t key) {
  return vt_hash_integer(((uint64_t) key.cme_iseq_id.value.value << 16) | key.position.value);
}

static bool location_equal(miteruby_location_key_t left, miteruby_location_key_t right) {
  return left.cme_iseq_id.value.value == right.cme_iseq_id.value.value && left.position.value == right.position.value;
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
  // Every VALUE held by miteruby is protected by the queue or one of the marking tables; other buffers hold copies.
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

  // Mark the verstable_mark_cme_iseq_map
  //
  // Note: Because `verstable_mark_cme_iseq_map` holds pairs of <cme, iseq>, we could be marking the same cme or iseq
  // more than once if it shows up in more than one pair. This is a bit of a classic space/time trade-off: we could
  // introduce another set just for marking, which would be less work at GC time but more memory for us to keep.
  // Something to keep in mind if Ruby's GC marking shows up as a hotspot?
  //
  // Note 2: While it would be tempting to consider marking only the cme when we know the iseq is the one the cme
  // points to, remember that we're marking **and pinning** so we really need to tell Ruby here to mark && pin both to
  // make sure Ruby doesn't move the iseq.
  for (
    verstable_mark_cme_iseq_map_itr itr = verstable_mark_cme_iseq_map_first(&state->mark_cme_iseq_map);
    !verstable_mark_cme_iseq_map_is_end(itr);
    itr = verstable_mark_cme_iseq_map_next(itr)
  ) {
    if (itr.data->key.cme != NULL) rb_gc_mark((VALUE) itr.data->key.cme);
    if (itr.data->key.iseq != NULL) rb_gc_mark((VALUE) itr.data->key.iseq);
  }

  mutex_unlock(&consumer_state.mutex);
}

static size_t consumer_size(const void *data) {
  const miteruby_consumer_state_t *state = data;

  mutex_lock(&consumer_state.mutex);

  size_t size = sizeof(*state) + sizeof(*state->raw_events_queue) +
    miteruby_allocator_alloc_size(state->interned_events_queue) +
    miteruby_allocator_alloc_size(state->mark_threads_set.buckets) +
    miteruby_allocator_alloc_size(state->mark_cme_iseq_map.buckets) +
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
  size_t interned_events_used_size = consumer_state.interned_events_count * sizeof(*consumer_state.interned_events_queue);
  size_t mark_threads_entries = verstable_mark_threads_set_size(&consumer_state.mark_threads_set);
  size_t mark_cme_iseq_entries = verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map);
  size_t location_entries = verstable_location_map_size(&consumer_state.location_map);
  miteruby_stack_dedup_stats_t stack_dedup = miteruby_stack_dedup_stats();
  miteruby_consumer_recorder_stats_t recorder = miteruby_consumer_recorder_stats();
  mutex_unlock(&consumer_state.mutex);

  VALUE arguments[] = {
    ID2SYM(rb_intern("miteruby_raw_events_queue_max_size_bytes")), SIZET2NUM(MITERUBY_RAW_EVENTS_QUEUE_CAPACITY_BYTES),
    ID2SYM(rb_intern("miteruby_interned_events_queue_max_size_bytes")),
      SIZET2NUM(INTERNED_EVENTS_QUEUE_MAX_CAPACITY * sizeof(*consumer_state.interned_events_queue)),
    ID2SYM(rb_intern("miteruby_interned_events_queue_used_size_bytes")), SIZET2NUM(interned_events_used_size),
    ID2SYM(rb_intern("miteruby_mark_threads_max_size_bytes")), SIZET2NUM(MARK_THREADS_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_mark_threads_entries")), SIZET2NUM(mark_threads_entries),
    ID2SYM(rb_intern("miteruby_mark_cme_iseq_max_size_bytes")), SIZET2NUM(MARK_CME_ISEQ_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_mark_cme_iseq_entries")), SIZET2NUM(mark_cme_iseq_entries),
    ID2SYM(rb_intern("miteruby_location_map_max_size_bytes")), SIZET2NUM(LOCATION_MAP_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_location_map_entries")), SIZET2NUM(location_entries),
    ID2SYM(rb_intern("miteruby_unique_stacks_array_max_size_bytes")), SIZET2NUM(stack_dedup.array_max_size_bytes),
    ID2SYM(rb_intern("miteruby_unique_stacks_array_used_size_bytes")), SIZET2NUM(stack_dedup.array_used_size_bytes),
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
  verstable_mark_cme_iseq_map_init(&consumer_state.mark_cme_iseq_map);
  verstable_location_map_init(&consumer_state.location_map);

  if (!miteruby_stack_dedup_init()) rb_raise(rb_eRuntimeError, "Failure during miteruby_stack_dedup_init");

  VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &consumer_typed_data, &consumer_state);

  // TODO: Let all this actually be garbage collected if it's not needed, now it's pinned forever
  rb_gc_register_mark_object(wrapper);
}

void miteruby_consumer_reset(void) {
  mutex_lock(&consumer_state.mutex);

  // Do this first so if we raise we don't leave weird intermediate state
  consumer_state.interned_events_count = 0;

  if (!miteruby_stack_dedup_reset()) {
    mutex_unlock(&consumer_state.mutex);
    rb_raise(rb_eRuntimeError, "Failure during miteruby_stack_dedup_reset");
  }

  miteruby_event_deduped_sample_t *new_queue = miteruby_allocator_alloc(INTERNED_EVENTS_QUEUE_MAX_CAPACITY * sizeof(*new_queue), "interned_events_queue");
  if (new_queue == NULL) {
    mutex_unlock(&consumer_state.mutex);
    rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.interned_events_queue");
  }

  miteruby_allocator_free(consumer_state.interned_events_queue);
  consumer_state.interned_events_queue = new_queue;
  consumer_state.interned_events_capacity = INTERNED_EVENTS_QUEUE_MAX_CAPACITY;

  verstable_mark_threads_set_clear(&consumer_state.mark_threads_set);
  verstable_mark_cme_iseq_map_clear(&consumer_state.mark_cme_iseq_map);
  verstable_location_map_clear(&consumer_state.location_map);

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
  if (reason == MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL) rb_raise(rb_eRuntimeError, "Miteruby mark_cme_iseq map is full");
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

void miteruby_consumer_prepare_serialize(VALUE recorder_instance) {
  miteruby_libdatadog_recorder_enforce_available(recorder_instance);
  mutex_lock(&consumer_state.mutex);
  rb_ensure(prepare_serialize_locked, recorder_instance, prepare_serialize_unlock_ensure, Qnil);
}

static VALUE prepare_serialize_locked(VALUE recorder_instance) {
  monotonic_to_system_epoch_state time_converter = MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER;

  for (size_t i = 0; i < consumer_state.interned_events_count; i++) {
    const miteruby_event_deduped_sample_t *event = &consumer_state.interned_events_queue[i];
    miteruby_stack_t stack = miteruby_stack_dedup_get(event->stack_id);
    miteruby_consumer_record_stack_sample(recorder_instance, event, stack, &time_converter);
  }

  consumer_state.interned_events_count = 0;

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

  size_t next_id = verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map);
  // We fail early if map is already at capacity
  if (next_id > UINT20_MAX) return MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL;
  verstable_mark_cme_iseq_map_itr entry = verstable_mark_cme_iseq_map_get_or_insert(
    &consumer_state.mark_cme_iseq_map, refs, (miteruby_cme_iseq_id_t) {.value = {.value = (unsigned int) next_id}}
  );
  if (verstable_mark_cme_iseq_map_is_end(entry)) return MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL;
  *id = entry.data->val;
  return MITERUBY_CONSUMER_OK;
}

// TODO: Temporary hack, until we have a better way of mapping ids to the data they represent at serialization time
miteruby_event_frame_refs_t miteruby_hack_id_to_frame_refs(miteruby_cme_iseq_id_t id) {
  // IDs are map values, so reverse lookup currently scans the map during serialization.
  for (
    verstable_mark_cme_iseq_map_itr entry = verstable_mark_cme_iseq_map_first(&consumer_state.mark_cme_iseq_map);
    !verstable_mark_cme_iseq_map_is_end(entry);
    entry = verstable_mark_cme_iseq_map_next(entry)
  ) {
    if (entry.data->val.value.value == id.value.value) return entry.data->key;
  }
  rb_raise(rb_eRuntimeError, "Miteruby unknown CME/ISEQ ID: %u", (unsigned int) id.value.value);
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
  if (consumer_state.interned_events_count == consumer_state.interned_events_capacity) return MITERUBY_CONSUMER_INTERNED_EVENTS_QUEUE_FULL;

  const miteruby_event_stack_sample_t *event = (const miteruby_event_stack_sample_t *)header;
  miteruby_stack_hash_t stack_hash = miteruby_stack_hash(event);
  miteruby_stack_dedup_result_t result = miteruby_stack_dedup_get_or_reserve(header->frame_count, stack_hash);
  if (result.error_storage_full) return MITERUBY_CONSUMER_DEDUP_STORAGE_FULL;
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
    if (!miteruby_stack_dedup_commit(result.ok.id, stack_hash, cursor)) return MITERUBY_CONSUMER_DEDUP_STORAGE_FULL;
  }

  miteruby_event_deduped_sample_t *deduped = &consumer_state.interned_events_queue[consumer_state.interned_events_count++];
  *deduped = (miteruby_event_deduped_sample_t) {.header = *header, .thread = event->thread, .stack_id = result.ok.id};
  deduped->header.type = MITERUBY_EVENT_DEDUPED_SAMPLE;
  deduped->header.size_bytes = sizeof(*deduped);

  return MITERUBY_CONSUMER_OK;
}
