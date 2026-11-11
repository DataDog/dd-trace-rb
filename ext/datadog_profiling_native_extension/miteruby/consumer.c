#include "allocator.h"
#include "raw_events_queue_marking.h"
#include "consumer.h"
#include "serializer.h"
#include "stack_dedup.h"
#include "compressed_deltas.h"

#include "../datadog_ruby_common.h"
#include "../helpers.h"
#include "../ruby_helpers.h"
#include "../setup_signal_handler.h"

#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <ruby/thread.h>
#include <threads.h>

#define MARK_THREADS_MAX_SIZE KiB_AS_BYTES(100)
// All 65,535 array entries fit in 131,072 set buckets; 2-byte IDs plus metadata need just over 512 KiB.
#define MARK_FRAME_MAX_SIZE MiB_AS_BYTES(1)
#define MARK_FRAME_ARRAY_CAPACITY UINT16_MAX // ~1 MiB total
// All 1,048,575 array entries fit in 2,097,152 set buckets; 4-byte IDs plus metadata need just over 12 MiB.
#define LOCATION_SET_MAX_SIZE MiB_AS_BYTES(13)
#define LOCATION_ARRAY_CAPACITY UINT20_MAX // ~4 MiB total

static void *mark_threads_calloc(size_t size);
static void *mark_frame_calloc(size_t size);
static uint64_t frame_hash(miteruby_frame_id_t id, const miteruby_mark_frame_array_t *array);
static bool frame_equal(miteruby_frame_id_t left, miteruby_frame_id_t right, const miteruby_mark_frame_array_t *array);
static void *location_calloc(size_t size);
static uint64_t location_hash(miteruby_location_id_t id, const miteruby_location_array_t *array);
static bool location_equal(miteruby_location_id_t left, miteruby_location_id_t right, const miteruby_location_array_t *array);

#define NAME verstable_mark_threads_set
#define KEY_TY VALUE
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#define MALLOC_FN mark_threads_calloc
#define FREE_FN miteruby_allocator_free_sized
#define IMPLEMENTATION_MODE
#include "hashtable/verstable.h"

#define NAME verstable_mark_frame_set
#define KEY_TY miteruby_frame_id_t
#define CTX_TY miteruby_mark_frame_array_t *
// Tiny hack: rely on Verstable's internal parameter name `table` to pass per-table context to hash/equality
// without changing Verstable
#define HASH_FN(key) frame_hash((key), table->ctx)
#define CMPR_FN(left, right) frame_equal((left), (right), table->ctx)
#define MALLOC_FN(size, ctx) mark_frame_calloc(size)
#define FREE_FN(ptr, size, ctx) miteruby_allocator_free_sized((ptr), (size))
#include "hashtable/verstable.h"

#define NAME verstable_location_set
#define KEY_TY miteruby_location_id_t
#define CTX_TY miteruby_location_array_t *
// Use the same context workaround as mark_frame_set above to look up each ID's location.
#define HASH_FN(key) location_hash((key), table->ctx)
#define CMPR_FN(left, right) location_equal((left), (right), table->ctx)
#define MALLOC_FN(size, ctx) location_calloc(size)
#define FREE_FN(ptr, size, ctx) miteruby_allocator_free_sized((ptr), (size))
#include "hashtable/verstable.h"

#define INTERNED_EVENTS_QUEUE_MAX_SIZE MiB_AS_BYTES(16)

typedef struct {
  miteruby_raw_events_queue_t *raw_events_queue;
  verstable_mark_threads_set mark_threads_set;
  verstable_mark_frame_set mark_frame_set;
  miteruby_mark_frame_array_t mark_frame_array;
  verstable_location_set location_set;
  miteruby_location_array_t location_array;

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
  MITERUBY_CONSUMER_MARK_FRAME_FULL,
  MITERUBY_CONSUMER_LOCATION_STORAGE_FULL,
  MITERUBY_CONSUMER_INVALID_FRAME,
} miteruby_consumer_exit_reason_t;

static VALUE consume_loop_body(VALUE args);
static VALUE consume_loop_ensure(VALUE args);
static void *consume_without_gvl(void *args);
static miteruby_consumer_exit_reason_t consume_without_gvl_internal(consumer_consume_loop_args *args);
static void consume_unblock(void *args);
static VALUE prepare_serialize_locked(VALUE args);
static VALUE prepare_serialize_ensure(VALUE unused);
static void reset_serialization_metadata(void);
static miteruby_consumer_exit_reason_t buffer_event(const miteruby_event_header_t *header);

static void *mark_threads_calloc(size_t size) {
  if (size > MARK_THREADS_MAX_SIZE) return NULL;
  return miteruby_allocator_alloc(size, "mark_threads");
}

static void *mark_frame_calloc(size_t size) {
  if (size > MARK_FRAME_MAX_SIZE) return NULL;
  return miteruby_allocator_alloc(size, "mark_frame");
}

static uint64_t frame_hash(miteruby_frame_id_t id, const miteruby_mark_frame_array_t *array) {
  return vt_wyhash(&array->entries[id.value], sizeof(miteruby_frame_t));
}

static bool frame_equal(miteruby_frame_id_t left, miteruby_frame_id_t right, const miteruby_mark_frame_array_t *array) {
  miteruby_frame_t left_frame = array->entries[left.value];
  miteruby_frame_t right_frame = array->entries[right.value];
  return left_frame.cme == right_frame.cme && left_frame.iseq == right_frame.iseq;
}

static void *location_calloc(size_t size) {
  if (size > LOCATION_SET_MAX_SIZE) return NULL;
  return miteruby_allocator_alloc(size, "location_set");
}

static uint64_t location_hash(miteruby_location_id_t id, const miteruby_location_array_t *array) {
  miteruby_location_t key = array->entries[id.value.value];
  return vt_hash_integer(((uint32_t) key.frame_id.value << 16) | key.bytecode_pos.value);
}

static bool location_equal(miteruby_location_id_t left, miteruby_location_id_t right, const miteruby_location_array_t *array) {
  miteruby_location_t left_location = array->entries[left.value.value];
  miteruby_location_t right_location = array->entries[right.value.value];
  return left_location.frame_id.value == right_location.frame_id.value && left_location.bytecode_pos.value == right_location.bytecode_pos.value;
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
  // Every VALUE held by the consumer is protected by the queue, thread set, or frame-reference array; other buffers hold copies.
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

  // Mark the mark_frame_array
  //
  // Note: Because `mark_frame_array` holds pairs of <cme, iseq>, we could be marking the same cme or iseq
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
  const miteruby_mark_frame_array_t *array = &state->mark_frame_array;
  rb_gc_mark_locations((const VALUE *)array->entries, (const VALUE *)&array->entries[array->count]);

  mutex_unlock(&consumer_state.mutex);
}

static size_t consumer_size(const void *data) {
  const miteruby_consumer_state_t *state = data;

  mutex_lock(&consumer_state.mutex);

  size_t size = sizeof(*state) + sizeof(*state->raw_events_queue) +
    miteruby_allocator_alloc_size(state->interned_events_queue) +
    miteruby_allocator_alloc_size(state->mark_threads_set.buckets) +
    miteruby_allocator_alloc_size(state->mark_frame_set.buckets) +
    miteruby_allocator_alloc_size(state->mark_frame_array.entries) +
    miteruby_allocator_alloc_size(state->location_set.buckets) +
    miteruby_allocator_alloc_size(state->location_array.entries) +
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
  size_t mark_frame_entries = consumer_state.mark_frame_array.count;
  size_t location_entries = consumer_state.location_array.count;
  miteruby_stack_dedup_stats_t stack_dedup = miteruby_stack_dedup_stats();
  mutex_unlock(&consumer_state.mutex);

  VALUE arguments[] = {
    ID2SYM(rb_intern("miteruby_raw_events_queue_max_size_bytes")), SIZET2NUM(MITERUBY_RAW_EVENTS_QUEUE_CAPACITY_BYTES),
    ID2SYM(rb_intern("miteruby_interned_events_queue_max_size_bytes")),
      SIZET2NUM(INTERNED_EVENTS_QUEUE_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_interned_events_queue_used_size_bytes")), SIZET2NUM(interned_events_used_size),
    ID2SYM(rb_intern("miteruby_mark_threads_max_size_bytes")), SIZET2NUM(MARK_THREADS_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_mark_threads_entries")), SIZET2NUM(mark_threads_entries),
    ID2SYM(rb_intern("miteruby_mark_frame_max_size_bytes")), SIZET2NUM(MARK_FRAME_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_mark_frame_array_max_size_bytes")),
      SIZET2NUM(MARK_FRAME_ARRAY_CAPACITY * sizeof(miteruby_frame_t)),
    ID2SYM(rb_intern("miteruby_mark_frame_array_entries")), SIZET2NUM(mark_frame_entries),
    ID2SYM(rb_intern("miteruby_mark_frame_entries")), SIZET2NUM(mark_frame_entries),
    ID2SYM(rb_intern("miteruby_location_set_max_size_bytes")), SIZET2NUM(LOCATION_SET_MAX_SIZE),
    ID2SYM(rb_intern("miteruby_location_array_max_size_bytes")),
      SIZET2NUM(LOCATION_ARRAY_CAPACITY * sizeof(miteruby_location_t)),
    ID2SYM(rb_intern("miteruby_location_array_entries")), SIZET2NUM(location_entries),
    ID2SYM(rb_intern("miteruby_location_set_entries")), SIZET2NUM(location_entries),
    ID2SYM(rb_intern("miteruby_unique_stacks_map_max_size_bytes")), SIZET2NUM(stack_dedup.map_max_size_bytes),
    ID2SYM(rb_intern("miteruby_unique_stacks_map_entries")), SIZET2NUM(stack_dedup.map_entries),
  };
  for (size_t i = 0; i < sizeof(arguments) / sizeof(*arguments); i += 2) rb_hash_aset(stats_as_hash, arguments[i], arguments[i + 1]);
}

miteruby_raw_events_queue_t *miteruby_consumer_init(void) {
  miteruby_raw_events_queue_t *raw_events_queue = miteruby_allocator_alloc(sizeof(*raw_events_queue), "raw_events_queue");
  if (raw_events_queue == NULL) raise_syserr(errno, "Failed to allocate miteruby raw events queue");
  if (miteruby_raw_events_queue_init(raw_events_queue) != 0) {
    int error = errno;
    miteruby_allocator_free(&raw_events_queue);
    raise_syserr(error, "Failed to initialize miteruby raw events queue");
  }

  if (mtx_init(&consumer_state.mutex, mtx_plain | mtx_recursive) != thrd_success) {
    miteruby_raw_events_queue_destroy(raw_events_queue);
    miteruby_allocator_free(&raw_events_queue);
    rb_raise(rb_eRuntimeError, "Failed to initialize miteruby.mutex");
  }

  consumer_state.raw_events_queue = raw_events_queue;
  verstable_mark_threads_set_init(&consumer_state.mark_threads_set);
  verstable_mark_frame_set_init(&consumer_state.mark_frame_set, &consumer_state.mark_frame_array);
  verstable_location_set_init(&consumer_state.location_set, &consumer_state.location_array);

  miteruby_stack_dedup_init();

  VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &consumer_typed_data, &consumer_state);

  // TODO: Let all this actually be garbage collected if it's not needed, now it's pinned forever
  rb_gc_register_mark_object(wrapper);

  return raw_events_queue;
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

  miteruby_frame_t *new_entries = miteruby_allocator_alloc(
    MARK_FRAME_ARRAY_CAPACITY * sizeof(*new_entries), "mark_frame_array"
  );
  if (new_entries == NULL) {
    miteruby_allocator_free(&new_queue);
    mutex_unlock(&consumer_state.mutex);
    rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.mark_frame_array");
  }

  miteruby_location_t *new_locations = miteruby_allocator_alloc(
    LOCATION_ARRAY_CAPACITY * sizeof(miteruby_location_t), "location_array"
  );
  if (new_locations == NULL) {
    miteruby_allocator_free(&new_entries);
    miteruby_allocator_free(&new_queue);
    mutex_unlock(&consumer_state.mutex);
    rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.location_array");
  }

  miteruby_allocator_free(&consumer_state.interned_events_queue);
  consumer_state.interned_events_queue = new_queue;
  consumer_state.interned_events_capacity = INTERNED_EVENTS_QUEUE_MAX_SIZE;

  verstable_mark_threads_set_clear(&consumer_state.mark_threads_set);
  verstable_mark_frame_set_clear(&consumer_state.mark_frame_set);
  verstable_location_set_clear(&consumer_state.location_set);

  miteruby_allocator_free(&consumer_state.mark_frame_array.entries);
  consumer_state.mark_frame_array = (miteruby_mark_frame_array_t) {
    .entries = new_entries,
    .count = 0,
    .capacity = MARK_FRAME_ARRAY_CAPACITY,
  };

  miteruby_allocator_free(&consumer_state.location_array.entries);
  consumer_state.location_array = (miteruby_location_array_t) {
    .entries = new_locations,
    .count = 0,
    .capacity = LOCATION_ARRAY_CAPACITY,
  };

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
  if (reason == MITERUBY_CONSUMER_MARK_FRAME_FULL) rb_raise(rb_eRuntimeError, "Miteruby mark_frame storage is full");
  if (reason == MITERUBY_CONSUMER_LOCATION_STORAGE_FULL) rb_raise(rb_eRuntimeError, "Miteruby location storage is full");

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
  if (pthread_sigmask(SIG_BLOCK, sigprof_signal_mask, NULL) != 0) rb_bug("Failed to block SIGPROF in miteruby consumer");

  for (;;) {
    miteruby_raw_events_queue_record_t record = miteruby_raw_events_queue_read(args->raw_events_queue, &args->interrupted);

    if (record.internal_error) return MITERUBY_CONSUMER_RAW_EVENTS_QUEUE_INTERNAL_ERROR;
    if (record.interrupted) return MITERUBY_CONSUMER_INTERRUPTED;
    if (record.end_of_stream) return MITERUBY_CONSUMER_END_OF_STREAM;
    // TODO: Report sample loss from record.rejected_count; the queue supplies no timestamp for rejected writes.
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

void miteruby_consumer_prepare_serialize(VALUE serializer_instance) {
  mutex_lock(&consumer_state.mutex);

  // This part of the work is done while holding the consumer lock so the consumer background thread is stopped...
  rb_ensure(prepare_serialize_locked, serializer_instance, prepare_serialize_ensure, Qnil);

  // ...`prepare_serialize_ensure` releases the lock as its last step so if we got here, the consumer background thread is free to continue.
  // The current thread (handling the serialization) will now release the GVL and do the rest of the serialization work without GVL.
  miteruby_serializer_exit_reason_t result = miteruby_serializer_serialize_no_gvl(serializer_instance);

  // Once we get here, we've re-acquired the GVL and can check if everything is OK or there was a failure and we need to raise.
  miteruby_serializer_raise_if_failed(result);
}

static VALUE prepare_serialize_locked(VALUE serializer_instance) {
  size_t interned_events_pos = consumer_state.interned_events_pos;

  // Reset all of these, they're only used to quick lookup during consumption data that lives in the arrays we use below
  //
  // This does mean that any failure during serialization means this data is discarded. That's OK because we don't
  // expect failures during serialization - they're errors we can't recover from.
  consumer_state.interned_events_pos = 0;
  miteruby_stack_dedup_reset();
  verstable_mark_frame_set_clear(&consumer_state.mark_frame_set);
  verstable_location_set_clear(&consumer_state.location_set);

  // If the serializer is "not available", something went wrong. To avoid accumulating/leaking state, we'll still
  // discard all of the state of the consumer (it's why we're checking here, after clearing the things above)
  // + the `prepare_serialize_ensure` will discard the rest.
  //
  // Afterwards, the consumer will be able to keep going, as if it had successfully serialized.
  miteruby_serializer_check_available(serializer_instance);

  // The existing interned_events_queue will become owned by the serializer, and the consumer gets a fresh new one
  uint8_t *new_queue = miteruby_allocator_alloc(INTERNED_EVENTS_QUEUE_MAX_SIZE, "interned_events_queue");
  if (new_queue == NULL) rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.interned_events_queue");
  uint8_t *interned_events_queue = consumer_state.interned_events_queue;
  consumer_state.interned_events_queue = new_queue;
  consumer_state.interned_events_capacity = INTERNED_EVENTS_QUEUE_MAX_SIZE;

  miteruby_serializer_exit_reason_t reason = miteruby_serializer_prepare_serialize(
    serializer_instance, interned_events_queue, interned_events_pos,
    &consumer_state.mark_frame_array, &consumer_state.location_array, &consumer_state.mark_threads_set
  );
  miteruby_serializer_raise_if_failed(reason);

  return Qnil;
}

static VALUE prepare_serialize_ensure(DDTRACE_UNUSED VALUE unused) {
  reset_serialization_metadata();
  mutex_unlock(&consumer_state.mutex);
  return Qnil;
}

static void reset_serialization_metadata(void) {
  // Frames are no longer dereferenced after preparation; retained threads are marked by the serializer.
  verstable_mark_threads_set_clear(&consumer_state.mark_threads_set);
  consumer_state.mark_frame_array.count = 0;

  consumer_state.location_array.count = 0;
}

static bool retain_thread(VALUE thread) {
  return !verstable_mark_threads_set_is_end(verstable_mark_threads_set_get_or_insert(&consumer_state.mark_threads_set, thread));
}

static miteruby_consumer_exit_reason_t retain_frame(miteruby_frame_t frame, miteruby_frame_id_t *id) {
  if (frame.cme == NULL && frame.iseq == NULL) return MITERUBY_CONSUMER_INVALID_FRAME;

  miteruby_mark_frame_array_t *array = &consumer_state.mark_frame_array;
  if (array->count >= array->capacity) return MITERUBY_CONSUMER_MARK_FRAME_FULL;

  // The set stores array indices, so its hash and equality functions need an index to find the cme/iseq pair.
  // Put the pair in the next unused slot so we can look it up using that slot's index. If the pair is already
  // in the set, we get its existing index back and can reuse this slot on the next lookup. Otherwise, the set
  // keeps the new index and we advance count to keep the pair in the array.
  array->entries[array->count] = frame;
  verstable_mark_frame_set_itr entry = verstable_mark_frame_set_get_or_insert(
    &consumer_state.mark_frame_set, (miteruby_frame_id_t) {.value = (uint16_t) array->count}
  );
  if (verstable_mark_frame_set_is_end(entry)) return MITERUBY_CONSUMER_MARK_FRAME_FULL;
  *id = entry.data->key;
  if (id->value == array->count) array->count++;
  return MITERUBY_CONSUMER_OK;
}

static miteruby_consumer_exit_reason_t intern_location(miteruby_location_t location, miteruby_location_id_t *id) {
  miteruby_location_array_t *array = &consumer_state.location_array;
  if (array->count >= array->capacity) return MITERUBY_CONSUMER_LOCATION_STORAGE_FULL;

  // Like retain_frame, put the pair in the next unused slot so the set can hash and compare it using an index.
  // A duplicate reuses its existing index; only a new entry keeps this slot and advances count.
  array->entries[array->count] = location;
  verstable_location_set_itr entry = verstable_location_set_get_or_insert(
    &consumer_state.location_set, (miteruby_location_id_t) {.value = {.value = (unsigned int) array->count}}
  );
  if (verstable_location_set_is_end(entry)) return MITERUBY_CONSUMER_LOCATION_STORAGE_FULL;
  *id = entry.data->key;
  if (id->value.value == array->count) array->count++;
  return MITERUBY_CONSUMER_OK;
}

static miteruby_consumer_exit_reason_t buffer_event(const miteruby_event_header_t *header) {
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
    const miteruby_bytecode_pos_t *bytecode_positions = (const miteruby_bytecode_pos_t *)&event->frames[header->frame_count];
    for (uint16_t i = 0; i < header->frame_count; i++) {
      miteruby_frame_id_t frame_id;
      miteruby_consumer_exit_reason_t reason = retain_frame(event->frames[i], &frame_id);
      if (reason != MITERUBY_CONSUMER_OK) return reason;
      miteruby_location_id_t location_id;
      reason = intern_location(
        (miteruby_location_t) {.frame_id = frame_id, .bytecode_pos = bytecode_positions[i]}, &location_id
      );
      if (reason != MITERUBY_CONSUMER_OK) return reason;
      // As we turn the (frame_id, bytecode_pos), into an id, we write those ids into the deduped stack storage
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
