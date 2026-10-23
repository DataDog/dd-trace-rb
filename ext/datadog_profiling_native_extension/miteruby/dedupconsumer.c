#include "dedupconsumer.h"
#include "dedupconsumer_recorder.h"
#include "buffer_marking.h"

#include <ruby/st.h>

#include "../datadog_ruby_common.h"
#include "../setup_signal_handler.h"
#include "../stack_recorder.h"
#include "../time_helpers.h"

#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <threads.h>

static once_flag mutexes_initialized = ONCE_FLAG_INIT;

// Lock order: consumed_events_mutex, then objects_to_mark_mutex. Recursive locking allows same-thread re-entry:
// marking and memory accounting can run while the owning thread holds both locks.
static mtx_t consumed_events_mutex;
static mtx_t objects_to_mark_mutex;

// Why "dedupconsumer"?
// This dedupconsumer bridges miteruby and the existing profiler APIs (specifically, StackRecorder).
// It's not the intended end-state for miteruby, and exists only to enable quicker experimentation.

#define CONSUMED_EVENTS_BUFFER_CHUNK_SIZE (1024U * 1024U)

static char *consumed_events_buffer = NULL;
static size_t consumed_events_pos = 0;
static size_t consumed_events_size = 0;

typedef struct {
  miteruby_buffer_t *buffer;
  // TODO: Move away from st_table because it can trigger Ruby GC, which we don't want from the dedupconsumer.
  // This may also interact with locking, e.g. insertion triggering GC, which then wants to mark.
  st_table *objects_to_mark;
} dedupconsumer_state;

static dedupconsumer_state state;

typedef struct {
  miteruby_buffer_t *buffer;
  VALUE recorder_instance;
} dedupconsumer_consume_loop_args;

static VALUE consume_loop_body(VALUE args);
static VALUE consume_loop_ensure(VALUE args);
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

static int mark_object(st_data_t object, DDTRACE_UNUSED st_data_t value, DDTRACE_UNUSED st_data_t unused) {
  // Use rb_gc_mark, not rb_gc_mark_movable: references held elsewhere are neither marked nor updated there,
  // so these objects must stay pinned at their current addresses.
  rb_gc_mark((VALUE) object);
  return ST_CONTINUE;
}

static void dedupconsumer_mark(void *data) {
  dedupconsumer_state *consumer_state = data;
  // Keep the event handoff paused across both scans so neither can miss a transferred reference.
  mutex_lock(&consumed_events_mutex);
  mutex_lock(&objects_to_mark_mutex);
  // This also blocks publishers while scanning the shared buffer. Holding both consumer locks is safe:
  // publishers never acquire them, and buffer marking masks SIGPROF before taking the producer lock.
  miteruby_buffer_mark(consumer_state->buffer);
  if (consumer_state->objects_to_mark != NULL) st_foreach(consumer_state->objects_to_mark, mark_object, 0);
  mutex_unlock(&objects_to_mark_mutex);
  mutex_unlock(&consumed_events_mutex);
}

static size_t dedupconsumer_size(const void *data) {
  const dedupconsumer_state *consumer_state = data;
  mutex_lock(&consumed_events_mutex);
  mutex_lock(&objects_to_mark_mutex);
  size_t size = sizeof(*consumer_state) + sizeof(*consumer_state->buffer) + consumed_events_size +
    (consumer_state->objects_to_mark == NULL ? 0 : st_memsize(consumer_state->objects_to_mark));
  mutex_unlock(&objects_to_mark_mutex);
  mutex_unlock(&consumed_events_mutex);
  return size;
}

static const rb_data_type_t dedupconsumer_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::Dedupconsumer",
  .function = {
    .dmark = dedupconsumer_mark,
    .dfree = NULL, // The state has static storage and its wrapper is permanently rooted.
    .dsize = dedupconsumer_size,
  },
};

// TODO: This is somewhat misnamed, as this marking is also used for the miniconsumer.
void miteruby_dedupconsumer_marking_init(miteruby_buffer_t *buffer) {
  call_once(&mutexes_initialized, initialize_mutexes);
  state.buffer = buffer;
  VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &dedupconsumer_typed_data, &state);
  // TODO: Let all this actually be garbage collected if it's not needed, now it's pinned forever
  rb_gc_register_mark_object(wrapper);
}

void miteruby_dedupconsumer_init(void) {
  mutex_lock(&consumed_events_mutex);
  mutex_lock(&objects_to_mark_mutex);

  char *new_buffer = calloc(1, CONSUMED_EVENTS_BUFFER_CHUNK_SIZE);
  if (new_buffer == NULL) rb_bug("Failed to allocate miteruby consumed events buffer");
  free(consumed_events_buffer);
  consumed_events_buffer = new_buffer;
  consumed_events_pos = 0;
  consumed_events_size = CONSUMED_EVENTS_BUFFER_CHUNK_SIZE;

  if (state.objects_to_mark == NULL) {
    state.objects_to_mark = st_init_numtable();
  } else {
    st_clear(state.objects_to_mark);
  }

  miteruby_dedupconsumer_recorder_init();
  mutex_unlock(&objects_to_mark_mutex);
  mutex_unlock(&consumed_events_mutex);
}

void miteruby_dedupconsumer_consume_loop(miteruby_buffer_t *buffer, VALUE recorder_instance) {
  enforce_recorder_instance(recorder_instance);
  dedupconsumer_consume_loop_args args = {
    .buffer = buffer,
    .recorder_instance = recorder_instance,
  };
  rb_ensure(consume_loop_body, (VALUE) &args, consume_loop_ensure, Qnil);
}

static VALUE consume_loop_body(VALUE args_ptr) {
  dedupconsumer_consume_loop_args *args = (dedupconsumer_consume_loop_args *) args_ptr;

  for (;;) {
    rb_thread_wait_for((struct timeval) {.tv_sec = 0, .tv_usec = 100000});
    // Buffer marking during GC may have unblocked SIGPROF since the previous iteration.
    block_sigprof_signal_handler_from_running_in_current_thread();
    miteruby_dedupconsumer_consume(args->buffer, args->recorder_instance);
  }
  return Qnil;
}

static VALUE consume_loop_ensure(DDTRACE_UNUSED VALUE unused) {
  unblock_sigprof_signal_handler_from_running_in_current_thread();
  return Qnil;
}

void miteruby_dedupconsumer_consume(miteruby_buffer_t *buffer, VALUE recorder_instance) {
  enforce_recorder_instance(recorder_instance);
  mutex_lock(&consumed_events_mutex);

  for (;;) {
    miteruby_buffer_record_t record = miteruby_buffer_read(buffer, false);
    if (record.data == NULL) {
      if (record.rejected_count != 0) continue;
      break;
    }

    buffer_event((const miteruby_event_header_t *)record.data);
  }
  mutex_unlock(&consumed_events_mutex);
}

void miteruby_dedupconsumer_prepare_serialize(VALUE recorder_instance) {
  enforce_recorder_instance(recorder_instance);
  mutex_lock(&consumed_events_mutex);
  rb_ensure(prepare_serialize_locked, recorder_instance, prepare_serialize_unlock_ensure, Qnil);
}

static VALUE prepare_serialize_locked(VALUE recorder_instance) {
  monotonic_to_system_epoch_state time_converter = MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER;
  for (size_t pos = 0; pos < consumed_events_pos;) {
    const miteruby_event_header_t *header = (const miteruby_event_header_t *)(consumed_events_buffer + pos);
    if (header->type == MITERUBY_EVENT_STACK_SAMPLE) {
      miteruby_dedupconsumer_record_stack_sample(recorder_instance, (const miteruby_event_stack_sample_t *)header, &time_converter);
    }
    pos += header->size_bytes;
  }
  consumed_events_pos = 0;
  return Qnil;
}

static VALUE prepare_serialize_unlock_ensure(DDTRACE_UNUSED VALUE unused) {
  mutex_unlock(&consumed_events_mutex);
  return Qnil;
}

static void buffer_event(const miteruby_event_header_t *header) {
  // Retain references before the next buffer read releases the record's GC protection.
  if (header->type == MITERUBY_EVENT_STACK_SAMPLE) {
    const miteruby_event_stack_sample_t *event = (const miteruby_event_stack_sample_t *)header;
    mutex_lock(&objects_to_mark_mutex);
    st_insert(state.objects_to_mark, (st_data_t) event->thread.value, 0);
    for (uint16_t i = 0; i < header->frame_count; i++) {
      if (event->refs[i].cme != NULL) st_insert(state.objects_to_mark, (st_data_t) event->refs[i].cme, 0);
      if (event->refs[i].iseq != NULL) st_insert(state.objects_to_mark, (st_data_t) event->refs[i].iseq, 0);
    }
    mutex_unlock(&objects_to_mark_mutex);
  }

  while (consumed_events_size - consumed_events_pos < header->size_bytes) {
    if (consumed_events_size > SIZE_MAX - CONSUMED_EVENTS_BUFFER_CHUNK_SIZE) rb_bug("Miteruby consumed events buffer size overflow");
    size_t new_size = consumed_events_size + CONSUMED_EVENTS_BUFFER_CHUNK_SIZE;
    char *new_buffer = realloc(consumed_events_buffer, new_size);
    if (new_buffer == NULL) rb_bug("Failed to grow miteruby consumed events buffer");
    consumed_events_buffer = new_buffer;
    consumed_events_size = new_size;
  }
  memcpy(consumed_events_buffer + consumed_events_pos, header, header->size_bytes);
  consumed_events_pos += header->size_bytes;
}
