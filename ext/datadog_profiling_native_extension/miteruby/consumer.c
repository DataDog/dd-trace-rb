#include "consumer.h"
#include "consumer_recorder.h"
#include "stack_dedup.h"
#include "buffer_marking.h"
#include "allocator.h"

#include "../datadog_ruby_common.h"
#include "../setup_signal_handler.h"
#include "libdatadog_recorder.h"
#include "../time_helpers.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <ruby/thread.h>
#include <threads.h>

static size_t objects_to_mark_allocated_bytes = 0;

static void *objects_to_mark_calloc(size_t size) {
  void *allocation = miteruby_allocator_alloc(size, "objects_to_mark");
  if (allocation != NULL) objects_to_mark_allocated_bytes += size;
  return allocation;
}

static void objects_to_mark_free(void *allocation, size_t size) {
  miteruby_allocator_free(allocation, size);
  objects_to_mark_allocated_bytes -= size;
}

#define NAME verstable_objects_to_mark_set
#define KEY_TY VALUE
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#define MALLOC_FN objects_to_mark_calloc
#define FREE_FN objects_to_mark_free
#include "verstable.h"

static once_flag mutexes_initialized = ONCE_FLAG_INIT;

// Lock order: consumed_events_mutex, then objects_to_mark_mutex. Recursive locking allows same-thread re-entry:
// marking and memory accounting can run while the owning thread holds both locks.
static mtx_t consumed_events_mutex;
static mtx_t objects_to_mark_mutex;

#define CONSUMED_EVENTS_BUFFER_CHUNK_CAPACITY (1024U * 1024U / sizeof(miteruby_event_deduped_sample_t))

static miteruby_event_deduped_sample_t *consumed_events_buffer = NULL;
static size_t consumed_events_count = 0;
static size_t consumed_events_capacity = 0;

typedef struct {
  miteruby_buffer_t *buffer;
  verstable_objects_to_mark_set objects_to_mark;
} consumer_state;

static consumer_state state;

typedef struct {
  miteruby_buffer_t *buffer;
  atomic_bool interrupted;
} consumer_consume_loop_args;

static VALUE consume_loop_body(VALUE args);
static VALUE consume_loop_ensure(VALUE args);
static void *consume_without_gvl(void *args);
static void consume_unblock(void *args);
static VALUE prepare_serialize_locked(VALUE recorder_instance);
static VALUE prepare_serialize_unlock_ensure(VALUE unused);
static void buffer_event(const miteruby_event_header_t *header);

static void mutex_lock(mtx_t *mutex) {
  if (mtx_lock(mutex) != thrd_success) rb_bug("Failed to lock miteruby consumer mutex");
}

static void mutex_unlock(mtx_t *mutex) {
  if (mtx_unlock(mutex) != thrd_success) rb_bug("Failed to unlock miteruby consumer mutex");
}

static void initialize_mutexes(void) {
  if (mtx_init(&consumed_events_mutex, mtx_recursive) != thrd_success) rb_bug("Failed to initialize miteruby consumer mutex");
  if (mtx_init(&objects_to_mark_mutex, mtx_recursive) != thrd_success) rb_bug("Failed to initialize miteruby consumer mutex");
}

static void consumer_mark(void *data) {
  consumer_state *consumer_state = data;
  // Keep the event handoff paused across both scans so neither can miss a transferred reference.
  mutex_lock(&consumed_events_mutex);
  mutex_lock(&objects_to_mark_mutex);
  // This also blocks publishers while scanning the shared buffer. Holding both consumer locks is safe:
  // publishers never acquire them, and buffer marking masks SIGPROF before taking the producer lock.
  miteruby_buffer_mark(consumer_state->buffer);
  for (
    verstable_objects_to_mark_set_itr itr = verstable_objects_to_mark_set_first(&consumer_state->objects_to_mark);
    !verstable_objects_to_mark_set_is_end(itr);
    itr = verstable_objects_to_mark_set_next(itr)
  ) {
    // Use rb_gc_mark, not rb_gc_mark_movable: references held elsewhere are neither marked nor updated there,
    // so these objects must stay pinned at their current addresses.
    rb_gc_mark(itr.data->key);
  }
  mutex_unlock(&objects_to_mark_mutex);
  mutex_unlock(&consumed_events_mutex);
}

static size_t consumer_size(const void *data) {
  const consumer_state *consumer_state = data;
  mutex_lock(&consumed_events_mutex);
  mutex_lock(&objects_to_mark_mutex);
  size_t size = sizeof(*consumer_state) + sizeof(*consumer_state->buffer) +
    consumed_events_capacity * sizeof(*consumed_events_buffer) +
    objects_to_mark_allocated_bytes + miteruby_stack_dedup_size();
  mutex_unlock(&objects_to_mark_mutex);
  mutex_unlock(&consumed_events_mutex);
  return size;
}

static const rb_data_type_t consumer_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::Consumer",
  .function = {
    .dmark = consumer_mark,
    .dfree = NULL, // The state has static storage and its wrapper is permanently rooted.
    .dsize = consumer_size,
  },
};

void miteruby_consumer_marking_init(miteruby_buffer_t *buffer) {
  call_once(&mutexes_initialized, initialize_mutexes);
  state.buffer = buffer;
  verstable_objects_to_mark_set_init(&state.objects_to_mark);
  miteruby_stack_dedup_init();
  VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &consumer_typed_data, &state);
  // TODO: Let all this actually be garbage collected if it's not needed, now it's pinned forever
  rb_gc_register_mark_object(wrapper);
}

void miteruby_consumer_init(void) {
  mutex_lock(&consumed_events_mutex);
  mutex_lock(&objects_to_mark_mutex);

  miteruby_event_deduped_sample_t *new_buffer = miteruby_allocator_alloc(CONSUMED_EVENTS_BUFFER_CHUNK_CAPACITY * sizeof(*new_buffer), "consumed_events_buffer");
  if (new_buffer == NULL) rb_bug("Failed to allocate miteruby consumed events buffer");
  miteruby_allocator_free(consumed_events_buffer, consumed_events_capacity * sizeof(*consumed_events_buffer));
  consumed_events_buffer = new_buffer;
  consumed_events_count = 0;
  consumed_events_capacity = CONSUMED_EVENTS_BUFFER_CHUNK_CAPACITY;

  miteruby_stack_dedup_reset();

  verstable_objects_to_mark_set_clear(&state.objects_to_mark);

  miteruby_consumer_recorder_init();
  mutex_unlock(&objects_to_mark_mutex);
  mutex_unlock(&consumed_events_mutex);
}

void miteruby_consumer_consume_loop(miteruby_buffer_t *buffer) {
  consumer_consume_loop_args args = {
    .buffer = buffer,
  };
  atomic_init(&args.interrupted, false);
  rb_ensure(consume_loop_body, (VALUE) &args, consume_loop_ensure, Qnil);
}

static VALUE consume_loop_body(VALUE args_ptr) {
  consumer_consume_loop_args *args = (consumer_consume_loop_args *) args_ptr;

  rb_thread_call_without_gvl(consume_without_gvl, args, consume_unblock, args);
  return Qnil;
}

static void consume_unblock(void *args_ptr) {
  consumer_consume_loop_args *args = args_ptr;
  atomic_store(&args->interrupted, true);
  miteruby_buffer_wake_consumer(args->buffer);
}

static void *consume_without_gvl(void *args_ptr) {
  consumer_consume_loop_args *args = args_ptr;
  // TODO: We toggle this here directly as existing helper assumes GVL
  if (pthread_sigmask(SIG_BLOCK, &sigprof_signal_mask, NULL) != 0) rb_bug("Failed to block SIGPROF in miteruby consumer");

  for (;;) {
    miteruby_buffer_record_t record = miteruby_buffer_read(args->buffer, &args->interrupted);
    if (record.interrupted || record.end_of_stream) return NULL;
    if (record.data == NULL) continue;

    // The borrowed event stays in shared-buffer marking until the next read, after this transfer completes.
    mutex_lock(&consumed_events_mutex);
    buffer_event((const miteruby_event_header_t *)record.data);
    mutex_unlock(&consumed_events_mutex);
  }
}

static VALUE consume_loop_ensure(DDTRACE_UNUSED VALUE unused) {
  unblock_sigprof_signal_handler_from_running_in_current_thread();
  return Qnil;
}

void miteruby_consumer_prepare_serialize(VALUE recorder_instance) {
  miteruby_libdatadog_recorder_enforce_available(recorder_instance);
  mutex_lock(&consumed_events_mutex);
  rb_ensure(prepare_serialize_locked, recorder_instance, prepare_serialize_unlock_ensure, Qnil);
}

static VALUE prepare_serialize_locked(VALUE recorder_instance) {
  monotonic_to_system_epoch_state time_converter = MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER;
  for (size_t i = 0; i < consumed_events_count; i++) {
    const miteruby_event_deduped_sample_t *event = &consumed_events_buffer[i];
    miteruby_event_stack_sample_view_t view = miteruby_stack_dedup_get(event->stack_id);
    miteruby_consumer_record_stack_sample(recorder_instance, event, view, &time_converter);
  }
  consumed_events_count = 0;
  return Qnil;
}

static VALUE prepare_serialize_unlock_ensure(DDTRACE_UNUSED VALUE unused) {
  mutex_unlock(&consumed_events_mutex);
  return Qnil;
}

static void retain_object(VALUE object) {
  if (verstable_objects_to_mark_set_is_end(verstable_objects_to_mark_set_get_or_insert(&state.objects_to_mark, object))) {
    rb_bug("Failed to grow miteruby objects_to_mark set");
  }
}

static void buffer_event(const miteruby_event_header_t *header) {
  // TODO: Handle overflow and other kinds of events
  if (header->type != MITERUBY_EVENT_STACK_SAMPLE) return;

  const miteruby_event_stack_sample_t *event = (const miteruby_event_stack_sample_t *)header;
  miteruby_event_stack_sample_view_t view = {
    .refs = (miteruby_event_frame_refs_t *)event->refs,
    .positions = (miteruby_event_frame_position_t *)&event->refs[header->frame_count],
    .frame_count = header->frame_count,
  };
  miteruby_stack_dedup_result_t result = miteruby_stack_dedup_get_or_insert(view);
  if (result.error_storage_full) rb_bug("Failed to deduplicate miteruby stack"); // TODO: Better handle storage full

  // Retain references before the next buffer read releases the record's GC protection.
  mutex_lock(&objects_to_mark_mutex);
  retain_object(event->thread.value);
  if (result.ok.inserted) {
    for (uint16_t i = 0; i < header->frame_count; i++) {
      if (event->refs[i].cme != NULL) retain_object((VALUE) event->refs[i].cme);
      if (event->refs[i].iseq != NULL) retain_object((VALUE) event->refs[i].iseq);
    }
  }
  mutex_unlock(&objects_to_mark_mutex);

  if (consumed_events_count == consumed_events_capacity) {
    if (consumed_events_capacity > SIZE_MAX / sizeof(*consumed_events_buffer) - CONSUMED_EVENTS_BUFFER_CHUNK_CAPACITY)
      rb_bug("Miteruby consumed events buffer size overflow");
    size_t new_capacity = consumed_events_capacity + CONSUMED_EVENTS_BUFFER_CHUNK_CAPACITY;
    miteruby_event_deduped_sample_t *new_buffer = miteruby_allocator_alloc(new_capacity * sizeof(*new_buffer), "consumed_events_buffer");
    if (new_buffer == NULL) rb_bug("Failed to grow miteruby consumed events buffer");
    memcpy(new_buffer, consumed_events_buffer, consumed_events_count * sizeof(*new_buffer));
    miteruby_allocator_free(consumed_events_buffer, consumed_events_capacity * sizeof(*consumed_events_buffer));
    consumed_events_buffer = new_buffer;
    consumed_events_capacity = new_capacity;
  }
  miteruby_event_deduped_sample_t *deduped = &consumed_events_buffer[consumed_events_count++];
  *deduped = (miteruby_event_deduped_sample_t) {.header = *header, .thread = event->thread, .stack_id = result.ok.id};
  deduped->header.type = MITERUBY_EVENT_DEDUPED_SAMPLE;
  deduped->header.size_bytes = sizeof(*deduped);
}
