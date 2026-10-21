#include "dedupconsumer.h"

#include <ruby/st.h>

#include "../collectors_stack.h"
#include "../datadog_ruby_common.h"
#include "../private_vm_api_access.h"
#include "../setup_signal_handler.h"
#include "../time_helpers.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <threads.h>

static once_flag mutexes_initialized = ONCE_FLAG_INIT;

// Lock order: consumed_events_mutex, then objects_to_mark_mutex. Recursive locking allows same-thread re-entry:
// GC marking takes only objects_to_mark_mutex; the memory-size callback takes both for memory accounting.
static mtx_t consumed_events_mutex;
static mtx_t objects_to_mark_mutex;

// Why "dedupconsumer"?
// This dedupconsumer bridges miteruby and the existing profiler APIs (specifically, StackRecorder).
// It's not the intended end-state for miteruby, and exists only to enable quicker experimentation.

#define THREAD_ID_LIMIT_CHARS 44
#define THREAD_INVOKE_LOCATION_LIMIT_CHARS 512
#define MITERUBY_DEBUG_SIGHANDLER_FRAME true
#define MITERUBY_DEBUG_ROOT_FRAME true
#define CONSUMED_EVENTS_BUFFER_CHUNK_SIZE (1024U * 1024U)

static char *consumed_events_buffer = NULL;
static size_t consumed_events_pos = 0;
static size_t consumed_events_size = 0;

typedef struct {
  // TODO: Move away from st_table because it can trigger Ruby GC, which we don't want from the dedupconsumer.
  // This may also interact with locking, e.g. insertion triggering GC, which then wants to mark.
  st_table *objects_to_mark;
} dedupconsumer_state;

static dedupconsumer_state state;

typedef struct {
  cpu_time_t cpu_time_at_previous_sample;
  monotonic_time_t monotonic_time_at_previous_sample;
} dedupconsumer_thread_context;

typedef struct {
  miteruby_buffer_t *buffer;
  VALUE recorder_instance;
} dedupconsumer_consume_loop_args;

// Ruby thread keys are marked and pinned via objects_to_mark.
static st_table *thread_contexts;

// Declared in Ruby's private iseq.h; redeclared here to avoid importing VM internals.
RUBY_EXTERN unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);

static int free_thread_context(DDTRACE_UNUSED st_data_t thread, st_data_t context, DDTRACE_UNUSED st_data_t unused);
static VALUE consume_loop_body(VALUE args);
static VALUE consume_loop_ensure(VALUE args);
static VALUE prepare_serialize_locked(VALUE recorder_instance);
static VALUE prepare_serialize_unlock_ensure(VALUE unused);
static void buffer_event(const miteruby_event_header_t *header);
static void record_stack_sample(
  VALUE recorder_instance,
  const miteruby_event_stack_sample_t *event,
  monotonic_to_system_epoch_state *time_converter
);
static sample_values sample_values_for(VALUE thread, monotonic_time_t monotonic_time, cpu_time_t cpu_time);
static dedupconsumer_thread_context *thread_context_for(VALUE thread, monotonic_time_t monotonic_time, cpu_time_t cpu_time);
static long update_and_get_time_since_previous_sample(dedupconsumer_thread_context *context, cpu_time_t current_time);
static ddog_CharSlice thread_name_label(VALUE thread, VALUE name, char *fallback, size_t fallback_size);

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
  mutex_lock(&objects_to_mark_mutex);
  if (consumer_state->objects_to_mark != NULL) st_foreach(consumer_state->objects_to_mark, mark_object, 0);
  mutex_unlock(&objects_to_mark_mutex);
}

static size_t dedupconsumer_size(const void *data) {
  const dedupconsumer_state *consumer_state = data;
  mutex_lock(&consumed_events_mutex);
  mutex_lock(&objects_to_mark_mutex);
  size_t size = sizeof(*consumer_state) + consumed_events_size +
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

void miteruby_dedupconsumer_init(void) {
  call_once(&mutexes_initialized, initialize_mutexes);
  mutex_lock(&consumed_events_mutex);
  mutex_lock(&objects_to_mark_mutex);

  char *new_buffer = calloc(1, CONSUMED_EVENTS_BUFFER_CHUNK_SIZE);
  if (new_buffer == NULL) rb_bug("Failed to allocate miteruby consumed events buffer");
  free(consumed_events_buffer);
  consumed_events_buffer = new_buffer;
  consumed_events_pos = 0;
  consumed_events_size = CONSUMED_EVENTS_BUFFER_CHUNK_SIZE;

  if (state.objects_to_mark == NULL) {
    VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &dedupconsumer_typed_data, &state);
    rb_gc_register_mark_object(wrapper);
    state.objects_to_mark = st_init_numtable();
  } else {
    st_clear(state.objects_to_mark);
  }

  if (thread_contexts == NULL) {
    thread_contexts = st_init_numtable();
  } else {
    st_foreach(thread_contexts, free_thread_context, 0);
  }
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

// TODO: Replace the fixed "had cpu" state with real categorization.
// TODO: Include capture-time trace identifiers and remove the temporary miteruby=1 label.
// TODO: Cache thread labels instead of fetching them for every sample.
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
      record_stack_sample(recorder_instance, (const miteruby_event_stack_sample_t *)header, &time_converter);
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

static void record_stack_sample(
  VALUE recorder_instance,
  const miteruby_event_stack_sample_t *event,
  monotonic_to_system_epoch_state *time_converter
) {
  VALUE thread = event->thread.value;
  sample_values values = sample_values_for(thread, event->header.timestamp, event->header.cpu_time);
  VALUE object_id = rb_obj_id(thread);
  uint64_t native_thread_id = is_thread_alive(thread) ? native_thread_id_for(thread) : 0;
  char thread_id[THREAD_ID_LIMIT_CHARS];
  snprintf(
    thread_id, sizeof(thread_id), "%"PRIu64" (%lu)",
    native_thread_id, (unsigned long) (FIXNUM_P(object_id) ? FIX2LONG(object_id) : -1)
  );

  VALUE thread_name = thread_name_for(thread);
  char fallback_name[THREAD_INVOKE_LOCATION_LIMIT_CHARS];
  ddog_prof_Label labels[] = {
    {.key = DDOG_CHARSLICE_C("thread id"), .str = {.ptr = thread_id, .len = strlen(thread_id)}},
    {.key = DDOG_CHARSLICE_C("thread name"), .str = thread_name_label(thread, thread_name, fallback_name, sizeof(fallback_name))},
    {.key = DDOG_CHARSLICE_C("state"), .str = DDOG_CHARSLICE_C("had cpu")},
    {.key = DDOG_CHARSLICE_C("miteruby"), .num = 1},
  };
  sample_labels sample_label_values = {
    .labels = {.ptr = labels, .len = sizeof(labels) / sizeof(labels[0])},
    .state_label = &labels[2],
    .end_timestamp_ns = monotonic_to_system_epoch_ns(time_converter, event->header.timestamp.ns),
  };

  uint16_t count = event->header.frame_count;
  uint8_t stack_status = event->header.flags & MITERUBY_EVENT_STACK_STATUS_MASK;
  bool unavailable = stack_status == MITERUBY_EVENT_STACK_UNAVAILABLE || count == 0;
  size_t frame_offset = MITERUBY_DEBUG_SIGHANDLER_FRAME && (event->header.flags & MITERUBY_EVENT_FROM_SIGNAL_HANDLER) ? 1 : 0;
  size_t location_count = (unavailable ? 1 : count) + frame_offset + (MITERUBY_DEBUG_ROOT_FRAME ? 1 : 0);
  ddog_prof_Location locations[location_count];
  if (MITERUBY_DEBUG_ROOT_FRAME) {
    locations[location_count - 1] = (ddog_prof_Location) {
      .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
      .function = {.name = DDOG_CHARSLICE_C("(sampled by miteruby)"), .filename = DDOG_CHARSLICE_C("")},
    };
  }
  if (frame_offset != 0) {
    locations[0] = (ddog_prof_Location) {
      .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
      .function = {.name = DDOG_CHARSLICE_C("(sampled in sighandler)"), .filename = DDOG_CHARSLICE_C("")},
    };
  }
  if (unavailable) {
    locations[frame_offset] = (ddog_prof_Location) {
      .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
      .function = {.name = DDOG_CHARSLICE_C(""), .filename = DDOG_CHARSLICE_C("In native code")},
    };
  } else {
    const miteruby_event_frame_position_t *positions = (const miteruby_event_frame_position_t *)&event->refs[count];
    ddog_CharSlice filename = DDOG_CHARSLICE_C("");
    int line = 0;

    for (uint16_t i = 0; i < count; i++) {
      const miteruby_event_frame_refs_t *frame = &event->refs[i];
      if (frame->iseq != NULL) {
        filename = char_slice_from_ruby_string(ddtrace_iseq_path(frame->iseq));
        line = positions[i].value == UINT16_MAX ? 0 : rb_iseq_line_no(frame->iseq, positions[i].value);
      }
      VALUE name = ddtrace_location_base_label(frame->cme, frame->iseq);
      // Walk root-first to inherit Ruby caller locations for C frames; libdatadog expects the opposite order.
      locations[frame_offset + count - 1 - i] = (ddog_prof_Location) {
        .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
        .function = {.name = name == Qfalse ? DDOG_CHARSLICE_C("") : char_slice_from_ruby_string(name), .filename = filename},
        .line = line,
      };
    }

    if (stack_status == MITERUBY_EVENT_STACK_TRUNCATED) {
      locations[frame_offset] = (ddog_prof_Location) {
        .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
        .function = {.name = DDOG_CHARSLICE_C("Truncated Frames"), .filename = DDOG_CHARSLICE_C("")},
      };
    }
  }
  record_sample(recorder_instance, (ddog_prof_Slice_Location) {.ptr = locations, .len = location_count}, values, sample_label_values);
  RB_GC_GUARD(thread_name);
}

static sample_values sample_values_for(VALUE thread, monotonic_time_t monotonic_time, cpu_time_t cpu_time) {
  dedupconsumer_thread_context *context = thread_context_for(thread, monotonic_time, cpu_time);

  sample_values values = {
    .cpu_time_ns = update_and_get_time_since_previous_sample(context, cpu_time),
    .wall_time_ns = monotonic_time.ns - context->monotonic_time_at_previous_sample.ns,
    .cpu_or_wall_samples = 1,
  };
  context->monotonic_time_at_previous_sample = monotonic_time;
  return values;
}

static dedupconsumer_thread_context *thread_context_for(VALUE thread, monotonic_time_t monotonic_time, cpu_time_t cpu_time) {
  st_data_t existing_context;
  if (st_lookup(thread_contexts, (st_data_t) thread, &existing_context)) return (dedupconsumer_thread_context *) existing_context;

  dedupconsumer_thread_context *context = ruby_xmalloc(sizeof(*context));
  *context = (dedupconsumer_thread_context) {
    .cpu_time_at_previous_sample = cpu_time,
    .monotonic_time_at_previous_sample = monotonic_time,
  };
  st_insert(thread_contexts, (st_data_t) thread, (st_data_t) context);
  return context;
}

static long update_and_get_time_since_previous_sample(dedupconsumer_thread_context *context, cpu_time_t current_time) {
  if (current_time.ns == INVALID_CPU_TIME.ns) return 0;

  long elapsed_ns = context->cpu_time_at_previous_sample.ns == INVALID_CPU_TIME.ns ?
    0 : current_time.ns - context->cpu_time_at_previous_sample.ns;
  context->cpu_time_at_previous_sample = current_time;
  return elapsed_ns;
}

static ddog_CharSlice thread_name_label(VALUE thread, VALUE name, char *fallback, size_t fallback_size) {
  if (name != Qnil) return char_slice_from_ruby_string(name);
  if (thread == rb_thread_main()) return DDOG_CHARSLICE_C("main");

  int line;
  VALUE filename = invoke_location_for(thread, &line);
  if (filename == Qnil) return DDOG_CHARSLICE_C("(Unnamed thread from native code)");

  const char *path = StringValueCStr(filename);
  const char *logging_path = "/lib/logging/diagnostic_context.rb";
  size_t path_length = strlen(path), logging_path_length = strlen(logging_path);
  if (path_length >= logging_path_length && strcmp(path + path_length - logging_path_length, logging_path) == 0)
    return DDOG_CHARSLICE_C("(Unnamed thread)");

  snprintf(fallback, fallback_size, "%s:%d", path, line);
  return (ddog_CharSlice) {.ptr = fallback, .len = strlen(fallback)};
}

static int free_thread_context(DDTRACE_UNUSED st_data_t thread, st_data_t context, DDTRACE_UNUSED st_data_t unused) {
  ruby_xfree((void *) context);
  return ST_DELETE;
}
