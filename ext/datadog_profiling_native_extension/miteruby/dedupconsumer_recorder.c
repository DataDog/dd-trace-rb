#include "dedupconsumer_recorder.h"

#include <ruby/st.h>

#include "../datadog_ruby_common.h"
#include "../private_vm_api_access.h"
#include "../stack_recorder.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#define THREAD_ID_LIMIT_CHARS 44
#define THREAD_INVOKE_LOCATION_LIMIT_CHARS 512
#define MITERUBY_DEBUG_SIGHANDLER_FRAME true
#define MITERUBY_DEBUG_ROOT_FRAME true

typedef struct {
  cpu_time_t cpu_time_at_previous_sample;
  monotonic_time_t monotonic_time_at_previous_sample;
} dedupconsumer_thread_context;

// Ruby thread keys are marked and pinned via objects_to_mark.
static st_table *thread_contexts;

// Declared in Ruby's private iseq.h; redeclared here to avoid importing VM internals.
RUBY_EXTERN unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);

static int free_thread_context(DDTRACE_UNUSED st_data_t thread, st_data_t context, DDTRACE_UNUSED st_data_t unused);
static sample_values sample_values_for(VALUE thread, monotonic_time_t monotonic_time, cpu_time_t cpu_time);
static dedupconsumer_thread_context *thread_context_for(VALUE thread, monotonic_time_t monotonic_time, cpu_time_t cpu_time);
static long update_and_get_time_since_previous_sample(dedupconsumer_thread_context *context, cpu_time_t current_time);
static ddog_CharSlice thread_name_label(VALUE thread, VALUE name, char *fallback, size_t fallback_size);

void miteruby_dedupconsumer_recorder_init(void) {
  if (thread_contexts == NULL) {
    thread_contexts = st_init_numtable();
  } else {
    st_foreach(thread_contexts, free_thread_context, 0);
  }
}

// TODO: Replace the fixed "had cpu" state with real categorization.
// TODO: Include capture-time trace identifiers and remove the temporary miteruby=1 label.
// TODO: Cache thread labels instead of fetching them for every sample.
void miteruby_dedupconsumer_record_stack_sample(
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
