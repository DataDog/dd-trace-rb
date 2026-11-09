#include "serializer.h"
#include "allocator.h"
#include "stack_dedup.h"
#include "compressed_deltas.h"
#include "pprof/pb_encode.h"
#include "pprof/pprof_fragments.pb.h"
#include "pprof/zstd.h"
#include "../datadog_ruby_common.h"
#include "../helpers.h"
#include "../time_helpers.h"

#include <string.h>
#include <inttypes.h>
#include <stdio.h>

RUBY_EXTERN unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);

enum { COMPRESSION_LEVEL = 1 };

// This is more than enough to contain any individual fragment, and allows us to accumulate a bit before feeding
// to zstd, to avoid overhead here.
#define MAX_UNCOMPRESSED_BUFFER_BYTES KiB_AS_BYTES(256)
#define UNCOMPRESSED_BUFFER_FLUSH_AFTER_BYTES KiB_AS_BYTES(128)

// Matches profiling-backend's 10 MiB limit for compressed profiles (search "Limits in profile size" in the wiki).
#define MAX_COMPRESSED_BUFFER_BYTES MiB_AS_BYTES(10)

// This limit is arbitrary, yet set to large enough that even when representing paths
// with lots of complex unicode characters it should be ample space.
#define MAX_STRING_TABLE_ENTRY_BYTES 1000

typedef struct {
  int64_t cpu_time_ns;
  uint32_t cpu_or_wall_samples;
  int64_t wall_time_ns;
  uint32_t alloc_samples;
  uint32_t alloc_samples_unscaled;
  int64_t timeline_wall_time_ns;
} miteruby_sample_values;

typedef struct {
  int64_t thread_name_string_id;
  int64_t thread_id_string_id;
  bool has_previous_sample;
  cpu_time_t cpu_time_at_previous_sample;
  monotonic_time_t monotonic_time_at_previous_sample;
} serializer_thread_context;

static void *thread_contexts_alloc(size_t size) {
  if (size > MiB_AS_BYTES(16)) return NULL;
  return miteruby_allocator_alloc(size, "serializer_thread_contexts");
}

#define NAME verstable_serializer_thread_contexts_map
#define KEY_TY VALUE
#define VAL_TY serializer_thread_context
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#define MALLOC_FN thread_contexts_alloc
#define FREE_FN miteruby_allocator_free_sized
#include "hashtable/verstable.h"

enum fixed_strings {
  PPROF_STRING_EMPTY = 0,
  PPROF_STRING_CPU_TIME,
  PPROF_STRING_NANOSECONDS,
  PPROF_STRING_CPU_SAMPLES,
  PPROF_STRING_COUNT,
  PPROF_STRING_WALL_TIME,
  PPROF_STRING_ALLOC_SAMPLES,
  PPROF_STRING_ALLOC_SAMPLES_UNSCALED,
  PPROF_STRING_TIMELINE,
  PPROF_STRING_THREAD_ID,
  PPROF_STRING_THREAD_NAME,
  PPROF_STRING_STATE,
  PPROF_STRING_HAD_CPU,
  PPROF_STRING_MITERUBY,
  PPROF_STRING_END_TIMESTAMP_NS,
  PPROF_STRING_SAMPLED_BY_MITERUBY,
  PPROF_STRING_SAMPLED_IN_SIGHANDLER,
  PPROF_STRING_IN_NATIVE_CODE,
  PPROF_STRING_TRUNCATED_FRAMES,
  PPROF_STRING_MAIN_THREAD,
  PPROF_STRING_UNNAMED_NATIVE_THREAD,
  PPROF_STRING_UNNAMED_THREAD,
  PPROF_STRING_FIRST_DYNAMIC,
};

static const char *const fixed_string_values[] = {
  [PPROF_STRING_EMPTY] = "",
  [PPROF_STRING_CPU_TIME] = "cpu-time",
  [PPROF_STRING_NANOSECONDS] = "nanoseconds",
  [PPROF_STRING_CPU_SAMPLES] = "cpu-samples",
  [PPROF_STRING_COUNT] = "count",
  [PPROF_STRING_WALL_TIME] = "wall-time",
  [PPROF_STRING_ALLOC_SAMPLES] = "alloc-samples",
  [PPROF_STRING_ALLOC_SAMPLES_UNSCALED] = "alloc-samples-unscaled",
  [PPROF_STRING_TIMELINE] = "timeline",
  [PPROF_STRING_THREAD_ID] = "thread id",
  [PPROF_STRING_THREAD_NAME] = "thread name",
  [PPROF_STRING_STATE] = "state",
  [PPROF_STRING_HAD_CPU] = "had cpu",
  [PPROF_STRING_MITERUBY] = "miteruby",
  [PPROF_STRING_END_TIMESTAMP_NS] = "end_timestamp_ns",
  [PPROF_STRING_SAMPLED_BY_MITERUBY] = "(sampled by miteruby)",
  [PPROF_STRING_SAMPLED_IN_SIGHANDLER] = "(sampled in sighandler)",
  [PPROF_STRING_IN_NATIVE_CODE] = "In native code",
  [PPROF_STRING_TRUNCATED_FRAMES] = "Truncated Frames",
  [PPROF_STRING_MAIN_THREAD] = "main",
  [PPROF_STRING_UNNAMED_NATIVE_THREAD] = "(Unnamed thread from native code)",
  [PPROF_STRING_UNNAMED_THREAD] = "(Unnamed thread)",
};

enum fixed_functions {
  PPROF_FUNCTION_ROOT = 1,
  PPROF_FUNCTION_SIGHANDLER,
  PPROF_FUNCTION_NATIVE,
  PPROF_FUNCTION_TRUNCATED,
  PPROF_FUNCTION_FIRST_DYNAMIC,
};

static const miteruby_pprof_fragment_function_function_t fixed_function_values[] = {
  [PPROF_FUNCTION_ROOT] = {.id = PPROF_FUNCTION_ROOT, .name = PPROF_STRING_SAMPLED_BY_MITERUBY, .filename = PPROF_STRING_EMPTY},
  [PPROF_FUNCTION_SIGHANDLER] = {.id = PPROF_FUNCTION_SIGHANDLER, .name = PPROF_STRING_SAMPLED_IN_SIGHANDLER, .filename = PPROF_STRING_EMPTY},
  [PPROF_FUNCTION_NATIVE] = {.id = PPROF_FUNCTION_NATIVE, .name = PPROF_STRING_EMPTY, .filename = PPROF_STRING_IN_NATIVE_CODE},
  [PPROF_FUNCTION_TRUNCATED] = {.id = PPROF_FUNCTION_TRUNCATED, .name = PPROF_STRING_TRUNCATED_FRAMES, .filename = PPROF_STRING_EMPTY},
};

enum fixed_locations {
  PPROF_LOCATION_ROOT = 1,
  PPROF_LOCATION_SIGHANDLER,
  PPROF_LOCATION_NATIVE,
  PPROF_LOCATION_TRUNCATED,
  PPROF_LOCATION_FIRST_DYNAMIC,
};

static const miteruby_pprof_fragment_location_location_t fixed_location_values[] = {
  [PPROF_LOCATION_ROOT] = {.id = PPROF_LOCATION_ROOT, .has_line = true, .line = {.function_id = PPROF_FUNCTION_ROOT}},
  [PPROF_LOCATION_SIGHANDLER] = {.id = PPROF_LOCATION_SIGHANDLER, .has_line = true, .line = {.function_id = PPROF_FUNCTION_SIGHANDLER}},
  [PPROF_LOCATION_NATIVE] = {.id = PPROF_LOCATION_NATIVE, .has_line = true, .line = {.function_id = PPROF_FUNCTION_NATIVE}},
  [PPROF_LOCATION_TRUNCATED] = {.id = PPROF_LOCATION_TRUNCATED, .has_line = true, .line = {.function_id = PPROF_FUNCTION_TRUNCATED}},
};

static const miteruby_pprof_fragment_sample_type_value_type_t sample_types[] = {
  {.type = PPROF_STRING_CPU_TIME, .unit = PPROF_STRING_NANOSECONDS},
  {.type = PPROF_STRING_CPU_SAMPLES, .unit = PPROF_STRING_COUNT},
  {.type = PPROF_STRING_WALL_TIME, .unit = PPROF_STRING_NANOSECONDS},
  {.type = PPROF_STRING_ALLOC_SAMPLES, .unit = PPROF_STRING_COUNT},
  {.type = PPROF_STRING_ALLOC_SAMPLES_UNSCALED, .unit = PPROF_STRING_COUNT},
  {.type = PPROF_STRING_TIMELINE, .unit = PPROF_STRING_NANOSECONDS},
};

typedef struct {
  uint8_t *uncompressed_serialization_buffer;
  uint8_t *compressed_serialization_buffer;
  size_t compressed_serialization_size;
  bool compression_finished;
  long start_time_ns;
  long finish_time_ns;
} miteruby_serializer_persistent_state_t;

typedef struct {
  // Buffer storage belongs to the persistent state; consumer inputs are borrowed while its mutex is held.
  miteruby_serializer_persistent_state_t *persistent_state;
  pb_ostream_t stream;
  ZSTD_outBuffer compressed_buffer;
  uint8_t *interned_events_queue;
  size_t interned_events_pos;
  const miteruby_mark_cme_iseq_array_t *cme_iseq_array;
  const miteruby_location_array_t *location_array;
  const verstable_mark_threads_set *threads_set;
  size_t function_count;
  size_t thread_count;
  long finish_time_ns;
  void *compression_workspace;
  ZSTD_CCtx *compression_context;
  verstable_serializer_thread_contexts_map thread_contexts;
  miteruby_serializer_exit_reason_t exit_reason;
} miteruby_serializer_prepare_serialization_state_t;

static miteruby_serializer_exit_reason_t miteruby_serializer_prepare_serialize_no_gvl(
  miteruby_serializer_prepare_serialization_state_t *state
);
static miteruby_serializer_exit_reason_t prepare_serialize(miteruby_serializer_prepare_serialization_state_t *state);

#define RETURN_IF_ERROR(expression) do { \
  miteruby_serializer_exit_reason_t exit_reason_ = (expression); \
  if (exit_reason_ != MITERUBY_SERIALIZER_OK) return exit_reason_; \
} while (0)

static void serializer_free(void *data) {
  miteruby_serializer_persistent_state_t *state = data;
  miteruby_allocator_free(state->uncompressed_serialization_buffer);
  miteruby_allocator_free(state->compressed_serialization_buffer);
  ruby_xfree(state);
}

static size_t serializer_size(const void *data) {
  const miteruby_serializer_persistent_state_t *state = data;
  return state ? sizeof(*state) + miteruby_allocator_alloc_size(state->uncompressed_serialization_buffer) +
    miteruby_allocator_alloc_size(state->compressed_serialization_buffer) : 0;
}

static const rb_data_type_t serializer_type = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::Serializer",
  .function = {.dfree = serializer_free, .dsize = serializer_size},
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static inline miteruby_serializer_persistent_state_t *get_state(VALUE serializer) {
  miteruby_serializer_persistent_state_t *state;
  TypedData_Get_Struct(serializer, miteruby_serializer_persistent_state_t, &serializer_type, state);
  return state;
}

void miteruby_serializer_raise_if_failed(miteruby_serializer_exit_reason_t reason) {
  switch (reason) {
    case MITERUBY_SERIALIZER_OK: return;
    case MITERUBY_SERIALIZER_COMPRESSED_BUFFER_FULL: rb_raise(rb_eRuntimeError, "Compressed streaming profile buffer is full");
    case MITERUBY_SERIALIZER_COMPRESSION_ERROR: rb_raise(rb_eRuntimeError, "Failed to compress streaming profile");
    case MITERUBY_SERIALIZER_COMPRESSION_WORKSPACE_SIZE_ERROR: rb_raise(rb_eRuntimeError, "Failed to size zstd workspace");
    case MITERUBY_SERIALIZER_COMPRESSION_WORKSPACE_ALLOCATION_ERROR: rb_memerror();
    case MITERUBY_SERIALIZER_COMPRESSION_CONTEXT_INIT_ERROR: rb_raise(rb_eRuntimeError, "Failed to initialize static zstd context");
    case MITERUBY_SERIALIZER_COMPRESSION_INIT_ERROR: rb_raise(rb_eRuntimeError, "Failed to initialize zstd stream");
    case MITERUBY_SERIALIZER_THREAD_CONTEXTS_FULL: rb_raise(rb_eRuntimeError, "Miteruby streaming thread contexts map is full");
    case MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK: rb_raise(rb_eRuntimeError, "Miteruby invalid compressed stack");
    case MITERUBY_SERIALIZER_STRING_TABLE_ENCODING_ERROR: rb_raise(rb_eRuntimeError, "Failed to encode streaming string table");
    case MITERUBY_SERIALIZER_LOCATION_ENCODING_ERROR: rb_raise(rb_eRuntimeError, "Failed to encode streaming location");
    case MITERUBY_SERIALIZER_SAMPLE_TYPE_ENCODING_ERROR: rb_raise(rb_eRuntimeError, "Failed to encode streaming sample type");
    case MITERUBY_SERIALIZER_FUNCTION_ENCODING_ERROR: rb_raise(rb_eRuntimeError, "Failed to encode streaming function");
    case MITERUBY_SERIALIZER_PROFILE_ENCODING_ERROR: rb_raise(rb_eRuntimeError, "Failed to encode streaming profile metadata");
    case MITERUBY_SERIALIZER_SAMPLE_SIZING_ERROR: rb_raise(rb_eRuntimeError, "Failed to size streaming sample");
    case MITERUBY_SERIALIZER_SAMPLE_ENCODING_ERROR: rb_raise(rb_eRuntimeError, "Failed to encode streaming sample");
  }
  rb_raise(rb_eRuntimeError, "Unknown miteruby serializer exit reason: %d", reason);
}

static miteruby_serializer_exit_reason_t initialize_compression(miteruby_serializer_prepare_serialization_state_t *state) {
  size_t workspace_size = ZSTD_estimateCStreamSize(COMPRESSION_LEVEL);
  if (ZSTD_isError(workspace_size)) return MITERUBY_SERIALIZER_COMPRESSION_WORKSPACE_SIZE_ERROR;
  state->compression_workspace = miteruby_allocator_alloc(workspace_size, "serializer_zstd");
  if (state->compression_workspace == NULL) return MITERUBY_SERIALIZER_COMPRESSION_WORKSPACE_ALLOCATION_ERROR;
  state->compression_context = ZSTD_initStaticCCtx(state->compression_workspace, workspace_size);
  if (state->compression_context == NULL) return MITERUBY_SERIALIZER_COMPRESSION_CONTEXT_INIT_ERROR;
  size_t result = ZSTD_initCStream(state->compression_context, COMPRESSION_LEVEL);
  if (ZSTD_isError(result)) return MITERUBY_SERIALIZER_COMPRESSION_INIT_ERROR;
  return MITERUBY_SERIALIZER_OK;
}

static miteruby_serializer_exit_reason_t compress_buffer(miteruby_serializer_prepare_serialization_state_t *state, ZSTD_EndDirective end_op) {
  ZSTD_inBuffer input = {.src = state->persistent_state->uncompressed_serialization_buffer, .size = state->stream.bytes_written};
  size_t result;
  do {
    if (state->compressed_buffer.pos == state->compressed_buffer.size) return MITERUBY_SERIALIZER_COMPRESSED_BUFFER_FULL;
    result = ZSTD_compressStream2(state->compression_context, &state->compressed_buffer, &input, end_op);
    if (ZSTD_isError(result)) return MITERUBY_SERIALIZER_COMPRESSION_ERROR;
  } while (input.pos < input.size || (end_op == ZSTD_e_end && result != 0));
  return MITERUBY_SERIALIZER_OK;
}

static miteruby_serializer_exit_reason_t flush_if_needed(miteruby_serializer_prepare_serialization_state_t *state) {
  if (RB_LIKELY(state->stream.bytes_written <= UNCOMPRESSED_BUFFER_FLUSH_AFTER_BYTES)) return MITERUBY_SERIALIZER_OK;

  RETURN_IF_ERROR(compress_buffer(state, ZSTD_e_continue));
  uint8_t *buffer = state->persistent_state->uncompressed_serialization_buffer;
  state->stream = pb_ostream_from_buffer(buffer, miteruby_allocator_alloc_size(buffer));
  return MITERUBY_SERIALIZER_OK;
}

static VALUE serializer_new(VALUE klass) {
  miteruby_serializer_persistent_state_t *state;
  VALUE serializer = TypedData_Make_Struct(klass, miteruby_serializer_persistent_state_t, &serializer_type, state);

  state->uncompressed_serialization_buffer = miteruby_allocator_alloc(MAX_UNCOMPRESSED_BUFFER_BYTES, "uncompressed_serialization_buffer");
  if (state->uncompressed_serialization_buffer == NULL) {
    rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.uncompressed_serialization_buffer");
  }

  state->compressed_serialization_buffer = miteruby_allocator_alloc(MAX_COMPRESSED_BUFFER_BYTES, "compressed_serialization_buffer");
  if (state->compressed_serialization_buffer == NULL) {
    rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.compressed_serialization_buffer");
  }

  state->start_time_ns = system_epoch_time_now_ns();
  state->finish_time_ns = state->start_time_ns;
  return serializer;
}

static miteruby_serializer_exit_reason_t thread_context_for(
  verstable_serializer_thread_contexts_map *thread_contexts, VALUE thread, serializer_thread_context **context
) {
  verstable_serializer_thread_contexts_map_itr entry = verstable_serializer_thread_contexts_map_get_or_insert(
    thread_contexts, thread, (serializer_thread_context) {0}
  );
  if (verstable_serializer_thread_contexts_map_is_end(entry)) return MITERUBY_SERIALIZER_THREAD_CONTEXTS_FULL;
  *context = &entry.data->val;
  return MITERUBY_SERIALIZER_OK;
}

static miteruby_sample_values sample_values_for(
  serializer_thread_context *context, const miteruby_event_deduped_sample_t *event
) {
  cpu_time_t cpu_time = event->header.cpu_time;
  monotonic_time_t monotonic_time = event->header.timestamp;
  if (!context->has_previous_sample) {
    context->cpu_time_at_previous_sample = cpu_time;
    context->monotonic_time_at_previous_sample = monotonic_time;
    context->has_previous_sample = true;
  }
  miteruby_sample_values values = {
    .wall_time_ns = monotonic_time.ns - context->monotonic_time_at_previous_sample.ns,
    .cpu_or_wall_samples = 1,
  };
  if (cpu_time.ns != INVALID_CPU_TIME.ns) {
    values.cpu_time_ns = context->cpu_time_at_previous_sample.ns == INVALID_CPU_TIME.ns ?
      0 : cpu_time.ns - context->cpu_time_at_previous_sample.ns;
    context->cpu_time_at_previous_sample = cpu_time;
  }
  context->monotonic_time_at_previous_sample = monotonic_time;
  return values;
}

// Fixed strings are followed by thread name/ID pairs in set order, then function name/filename
// pairs in CME/ISEQ array order. Every thread reserves two strings, including fallback names.
static int64_t string_table_id_for(uint64_t function_id, size_t thread_count) {
  return PPROF_STRING_FIRST_DYNAMIC + thread_count * 2 + function_id * 2;
}

static uint64_t function_id_for(uint64_t cme_iseq_index) {
  return PPROF_FUNCTION_FIRST_DYNAMIC + cme_iseq_index;
}

static uint64_t location_id_for(uint64_t location_index) {
  return PPROF_LOCATION_FIRST_DYNAMIC + location_index;
}

static miteruby_serializer_exit_reason_t read_location_ids(miteruby_stack_t stack, uint64_t *location_ids) {
  const uint8_t *cursor = stack.ids;
  uint20_t previous_value = {0};
  for (uint16_t i = 0; i < stack.frame_count; i++) {
    miteruby_location_id_t location_id;

    if (!miteruby_compressed_deltas_read(previous_value, &location_id.value, &cursor, stack.end))
      return MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK;

    previous_value = location_id.value;
    // Interned stacks are root-first; pprof samples are leaf-first.
    location_ids[stack.frame_count - 1 - i] = location_id_for(location_id.value.value);
  }
  if (cursor != stack.end) return MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK;
  return MITERUBY_SERIALIZER_OK;
}

static miteruby_serializer_exit_reason_t emit_string_table_entry(pb_ostream_t *stream, const char *string, size_t length) {
  if (length > MAX_STRING_TABLE_ENTRY_BYTES) length = MAX_STRING_TABLE_ENTRY_BYTES;

  if (!pb_encode_tag(stream, PB_WT_STRING, MITERUBY_PPROF_FRAGMENT_STRING_TABLE_STRING_TABLE_TAG) ||
      !pb_encode_string(stream, (const pb_byte_t *) string, length))
    return MITERUBY_SERIALIZER_STRING_TABLE_ENCODING_ERROR;

  return MITERUBY_SERIALIZER_OK;
}

static miteruby_serializer_exit_reason_t emit_thread_name(pb_ostream_t *stream, VALUE thread) {
  VALUE name = thread_name_for(thread);
  if (name != Qnil) {
    return emit_string_table_entry(stream, RSTRING_PTR(name), RSTRING_LEN(name));
  }

  const char *fallback;
  char invoke_location[512];
  if (thread == rb_thread_main()) {
    fallback = fixed_string_values[PPROF_STRING_MAIN_THREAD];
  } else {
    int line;
    VALUE filename = invoke_location_for(thread, &line);
    if (filename == Qnil) {
      fallback = fixed_string_values[PPROF_STRING_UNNAMED_NATIVE_THREAD];
    } else {
      const char *path = StringValueCStr(filename);
      const char *logging_path = "/lib/logging/diagnostic_context.rb";
      size_t path_length = strlen(path), logging_path_length = strlen(logging_path);
      if (path_length >= logging_path_length && strcmp(path + path_length - logging_path_length, logging_path) == 0) {
        fallback = fixed_string_values[PPROF_STRING_UNNAMED_THREAD];
      } else {
        snprintf(invoke_location, sizeof(invoke_location), "%s:%d", path, line);
        fallback = invoke_location;
      }
    }
  }
  return emit_string_table_entry(stream, fallback, strlen(fallback));
}

static miteruby_serializer_exit_reason_t emit_thread_id(pb_ostream_t *stream, VALUE thread) {
  VALUE object_id = rb_obj_id(thread);
  uint64_t native_thread_id = is_thread_alive(thread) ? native_thread_id_for(thread) : 0;
  char thread_id[44];
  snprintf(
    thread_id, sizeof(thread_id), "%"PRIu64" (%lu)",
    native_thread_id, (unsigned long) (FIXNUM_P(object_id) ? FIX2LONG(object_id) : -1)
  );
  return emit_string_table_entry(stream, thread_id, strlen(thread_id));
}

static miteruby_serializer_exit_reason_t emit_location_fragment(
  pb_ostream_t *stream, uint64_t location_id, uint64_t function_id, int64_t line
) {
  miteruby_pprof_fragment_location_t fragment = {
    .has_location = true,
    .location = {
      .id = location_id,
      .has_line = true,
      .line = {.function_id = function_id, .line = line},
    },
  };
  if (!pb_encode(stream, MITERUBY_PPROF_FRAGMENT_LOCATION_FIELDS, &fragment))
    return MITERUBY_SERIALIZER_LOCATION_ENCODING_ERROR;
  return MITERUBY_SERIALIZER_OK;
}

static bool encode_tag_and_varint(pb_ostream_t *stream, pb_wire_type_t wire_type, uint32_t tag, uint64_t value) {
  return pb_encode_tag(stream, wire_type, tag) && pb_encode_varint(stream, value);
}

static bool encode_values(pb_ostream_t *stream, uint32_t tag, const uint64_t *values, size_t count) {
  pb_ostream_t sizing = PB_OSTREAM_SIZING;
  for (size_t i = 0; i < count; i++) {
    if (!pb_encode_varint(&sizing, values[i])) return false;
  }
  if (!encode_tag_and_varint(stream, PB_WT_STRING, tag, sizing.bytes_written)) return false;
  for (size_t i = 0; i < count; i++) {
    if (!pb_encode_varint(stream, values[i])) return false;
  }
  return true;
}

static bool encode_sample(
  pb_ostream_t *stream, const uint64_t *location_ids, size_t location_count, const uint64_t *values, size_t value_count,
  const miteruby_pprof_fragment_sample_sample_label_t *labels, size_t label_count
) {
  if (!encode_values(stream, MITERUBY_PPROF_FRAGMENT_SAMPLE_SAMPLE_LOCATION_ID_TAG, location_ids, location_count) ||
      !encode_values(stream, MITERUBY_PPROF_FRAGMENT_SAMPLE_SAMPLE_VALUE_TAG, values, value_count)) return false;
  for (size_t i = 0; i < label_count; i++) {
    if (!pb_encode_tag(stream, PB_WT_STRING, MITERUBY_PPROF_FRAGMENT_SAMPLE_SAMPLE_LABEL_TAG) ||
        !pb_encode_submessage(stream, MITERUBY_PPROF_FRAGMENT_SAMPLE_SAMPLE_LABEL_FIELDS, &labels[i])) return false;
  }
  return true;
}

static miteruby_serializer_exit_reason_t emit_sample_fragment(
  pb_ostream_t *stream, const uint64_t *location_ids, size_t location_count, miteruby_sample_values values,
  const serializer_thread_context *context, int64_t end_timestamp_ns
) {
  uint64_t sample_values[] = {
    (uint64_t) values.cpu_time_ns, values.cpu_or_wall_samples, (uint64_t) values.wall_time_ns,
    values.alloc_samples, values.alloc_samples_unscaled, (uint64_t) values.timeline_wall_time_ns,
  };
  miteruby_pprof_fragment_sample_sample_label_t labels[] = {
    {.key = PPROF_STRING_THREAD_ID, .str = context->thread_id_string_id},
    {.key = PPROF_STRING_THREAD_NAME, .str = context->thread_name_string_id},
    {.key = PPROF_STRING_STATE, .str = PPROF_STRING_HAD_CPU},
    {.key = PPROF_STRING_MITERUBY, .num = 1},
    {.key = PPROF_STRING_END_TIMESTAMP_NS, .num = end_timestamp_ns},
  };
  size_t value_count = sizeof(sample_values) / sizeof(sample_values[0]);
  size_t label_count = sizeof(labels) / sizeof(labels[0]);
  pb_ostream_t sizing = PB_OSTREAM_SIZING;
  if (!encode_sample(&sizing, location_ids, location_count, sample_values, value_count, labels, label_count))
    return MITERUBY_SERIALIZER_SAMPLE_SIZING_ERROR;
  if (!encode_tag_and_varint(stream, PB_WT_STRING, MITERUBY_PPROF_FRAGMENT_SAMPLE_SAMPLE_TAG, sizing.bytes_written) ||
      !encode_sample(stream, location_ids, location_count, sample_values, value_count, labels, label_count))
    return MITERUBY_SERIALIZER_SAMPLE_ENCODING_ERROR;
  return MITERUBY_SERIALIZER_OK;
}

static VALUE prepare_serialize_body(VALUE state_value) {
  miteruby_serializer_prepare_serialization_state_t *state = (miteruby_serializer_prepare_serialization_state_t *)state_value;
  state->exit_reason = prepare_serialize(state);
  return Qnil;
}

static VALUE prepare_serialize_cleanup(VALUE state_value) {
  miteruby_serializer_prepare_serialization_state_t *state = (miteruby_serializer_prepare_serialization_state_t *)state_value;
  miteruby_allocator_free(state->compression_workspace);
  state->compression_workspace = NULL;
  state->compression_context = NULL;
  verstable_serializer_thread_contexts_map_cleanup(&state->thread_contexts);
  return Qnil;
}

miteruby_serializer_exit_reason_t miteruby_serializer_prepare_serialize(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  const miteruby_mark_cme_iseq_array_t *cme_iseq_array, const miteruby_location_array_t *location_array,
  const verstable_mark_threads_set *threads_set
) {
  miteruby_serializer_persistent_state_t *persistent_state = get_state(serializer);
  persistent_state->compression_finished = false;
  persistent_state->compressed_serialization_size = 0;
  miteruby_serializer_prepare_serialization_state_t state = {
    .persistent_state = persistent_state,
    .stream = pb_ostream_from_buffer(
      persistent_state->uncompressed_serialization_buffer, miteruby_allocator_alloc_size(persistent_state->uncompressed_serialization_buffer)
    ),
    .compressed_buffer = {
      .dst = persistent_state->compressed_serialization_buffer,
      .size = miteruby_allocator_alloc_size(persistent_state->compressed_serialization_buffer),
    },
    .interned_events_queue = interned_events_queue,
    .interned_events_pos = interned_events_pos,
    .cme_iseq_array = cme_iseq_array,
    .location_array = location_array,
    .threads_set = threads_set,
    .finish_time_ns = system_epoch_time_now_ns(),
  };
  verstable_serializer_thread_contexts_map_init(&state.thread_contexts);
  rb_ensure(prepare_serialize_body, (VALUE)&state, prepare_serialize_cleanup, (VALUE)&state);
  if (state.exit_reason == MITERUBY_SERIALIZER_OK) {
    persistent_state->compressed_serialization_size = state.compressed_buffer.pos;
    persistent_state->finish_time_ns = state.finish_time_ns;
    persistent_state->compression_finished = true;
  }
  RB_GC_GUARD(serializer);
  return state.exit_reason;
}

static miteruby_serializer_exit_reason_t prepare_serialize(miteruby_serializer_prepare_serialization_state_t *state) {
  RETURN_IF_ERROR(initialize_compression(state));
  pb_ostream_t *stream = &state->stream;
  const miteruby_mark_cme_iseq_array_t *cme_iseq_array = state->cme_iseq_array;
  const miteruby_location_array_t *location_array = state->location_array;
  const verstable_mark_threads_set *threads_set = state->threads_set;

  // Design note - Currently we need the GVL to:
  //
  // * Build thread contexts + emitting thread name/id
  // * Compute line numbers
  // * Emit frame names && filenames
  //
  // Yet, if we wanted to fully release the GVL during serialization, we could cache all of those across multiple
  // serializations, and reuse their results. Thus, on every serialization, we'd just need to make sure our caches
  // have everything (possibly by checking ahead of time, again without GVL, and only requiring GVL during a brief period
  // to get whatever's new/missing).
  //
  // The trade-off of enabling such "no-GVL" serialization is increased memory usage: we'd be copying a lot of
  // strings that already live inside the Ruby heap.
  //
  // For now, we do something slightly simpler below: we make sure to serialize all the things that require GVL +
  // their prerequisite steps first; and then we release the GVL for the rest of the work.

  // 1. Emit FragmentStringTable: Fixed strings (Does not require GVL)
  for (size_t i = 0; i < sizeof(fixed_string_values) / sizeof(fixed_string_values[0]); i++) {
    const char *string = fixed_string_values[i];
    RETURN_IF_ERROR(emit_string_table_entry(stream, string, strlen(string)));
    RETURN_IF_ERROR(flush_if_needed(state));
  }

  // 2. Emit FragmentStringTable: From profile data - threads (Requires GVL, depends: 1)
  int64_t thread_string_id = PPROF_STRING_FIRST_DYNAMIC;
  for (
    verstable_mark_threads_set_itr entry = verstable_mark_threads_set_first(threads_set);
    !verstable_mark_threads_set_is_end(entry);
    entry = verstable_mark_threads_set_next(entry)
  ) {
    VALUE thread = entry.data->key;
    serializer_thread_context *context;
    RETURN_IF_ERROR(thread_context_for(&state->thread_contexts, thread, &context));
    context->thread_name_string_id = thread_string_id++;
    context->thread_id_string_id = thread_string_id++;
    // Upcall into Ruby: Thread metadata (name, id, etc)
    RETURN_IF_ERROR(emit_thread_name(stream, thread));
    RETURN_IF_ERROR(emit_thread_id(stream, thread));
    RETURN_IF_ERROR(flush_if_needed(state));
  }

  // 3. Emit FragmentStringTable: From profile data - frame names and filenames (Requires GVL, depends: 2)
  char qualified_name[4096];
  for (size_t i = 0; i < cme_iseq_array->count; i++) {
    miteruby_event_frame_refs_t refs = cme_iseq_array->entries[i];
    // Upcall into Ruby: Class names, method names, method metadata
    ssize_t written = ddtrace_location_label(refs.cme, refs.iseq, qualified_name, sizeof(qualified_name));
    if (written > 0) {
      RETURN_IF_ERROR(emit_string_table_entry(stream, qualified_name, written));
    } else {
      VALUE name = ddtrace_location_base_label(refs.cme, refs.iseq);
      RETURN_IF_ERROR(emit_string_table_entry(
        stream, name == Qfalse ? "" : RSTRING_PTR(name), name == Qfalse ? 0 : RSTRING_LEN(name)
      ));
    }
    RETURN_IF_ERROR(flush_if_needed(state));

    // Upcall into Ruby: Method metadata, filenames
    if (refs.iseq != NULL) {
      VALUE filename = ddtrace_iseq_path(refs.iseq);
      RETURN_IF_ERROR(emit_string_table_entry(stream, RSTRING_PTR(filename), RSTRING_LEN(filename)));
    } else {
      const char *filename = "(TODO: resolve filename for cfuncs)";
      RETURN_IF_ERROR(emit_string_table_entry(stream, filename, strlen(filename)));
    }
    RETURN_IF_ERROR(flush_if_needed(state));
  }

  // 4. Emit FragmentLocation: Fixed placeholders (Does not require GVL)
  for (size_t i = 1; i < sizeof(fixed_location_values) / sizeof(fixed_location_values[0]); i++) {
    const miteruby_pprof_fragment_location_location_t *location = &fixed_location_values[i];
    RETURN_IF_ERROR(emit_location_fragment(stream, location->id, location->line.function_id, location->line.line));
    RETURN_IF_ERROR(flush_if_needed(state));
  }

  // 5. Emit FragmentLocation: From profile data (Requires GVL)
  for (size_t i = 0; i < location_array->count; i++) {
    miteruby_location_t location = location_array->entries[i];
    const rb_iseq_t *iseq = cme_iseq_array->entries[location.cme_iseq_id.value].iseq;
    // Upcall into Ruby: rb_iseq_line_no -> Calculate line number
    int64_t line = iseq != NULL && location.position.value != UINT16_MAX ? rb_iseq_line_no(iseq, location.position.value) : 0;
    RETURN_IF_ERROR(emit_location_fragment(stream, location_id_for(i), function_id_for(location.cme_iseq_id.value), line));
    RETURN_IF_ERROR(flush_if_needed(state));
  }

  state->function_count = cme_iseq_array->count;
  state->thread_count = verstable_mark_threads_set_size(threads_set);

  // From here, we can release the GVL, as all of the steps that needed GVL directly or indirectly (+ any of their dependencies)
  // have been serialized.
  return miteruby_serializer_prepare_serialize_no_gvl(state);
}

static miteruby_serializer_exit_reason_t miteruby_serializer_prepare_serialize_no_gvl(
  miteruby_serializer_prepare_serialization_state_t *state
) {
  pb_ostream_t *stream = &state->stream;
  uint8_t *interned_events_queue = state->interned_events_queue;
  size_t interned_events_pos = state->interned_events_pos;
  size_t function_count = state->function_count;
  size_t thread_count = state->thread_count;
  long finish_time_ns = state->finish_time_ns;
  monotonic_to_system_epoch_state time_converter = MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER;

  // 6. Emit FragmentSampleType (Does not require GVL)
  for (size_t i = 0; i < sizeof(sample_types) / sizeof(sample_types[0]); i++) {
    miteruby_pprof_fragment_sample_type_t fragment = {.has_sample_type = true, .sample_type = sample_types[i]};
    if (!pb_encode(stream, MITERUBY_PPROF_FRAGMENT_SAMPLE_TYPE_FIELDS, &fragment))
      return MITERUBY_SERIALIZER_SAMPLE_TYPE_ENCODING_ERROR;
    RETURN_IF_ERROR(flush_if_needed(state));
  }

  // 7. Emit FragmentFunction: Fixed placeholders (Does not require GVL)
  for (size_t i = 1; i < sizeof(fixed_function_values) / sizeof(fixed_function_values[0]); i++) {
    miteruby_pprof_fragment_function_t fragment = {.has_function = true, .function = fixed_function_values[i]};
    if (!pb_encode(stream, MITERUBY_PPROF_FRAGMENT_FUNCTION_FIELDS, &fragment))
      return MITERUBY_SERIALIZER_FUNCTION_ENCODING_ERROR;
    RETURN_IF_ERROR(flush_if_needed(state));
  }

  // 8. Emit FragmentFunction: From profile data (Does not require GVL)
  for (size_t i = 0; i < function_count; i++) {
    int64_t name_id = string_table_id_for(i, thread_count);
    miteruby_pprof_fragment_function_t fragment = {
      .has_function = true,
      .function = {.id = function_id_for(i), .name = name_id, .filename = name_id + 1},
    };
    if (!pb_encode(stream, MITERUBY_PPROF_FRAGMENT_FUNCTION_FIELDS, &fragment))
      return MITERUBY_SERIALIZER_FUNCTION_ENCODING_ERROR;
    RETURN_IF_ERROR(flush_if_needed(state));
  }

  // 9. Emit FragmentProfile (Does not require GVL)
  int64_t duration_ns = finish_time_ns - state->persistent_state->start_time_ns;
  miteruby_pprof_fragment_profile_t profile = {
    .time_nanos = state->persistent_state->start_time_ns,
    .duration_nanos = duration_ns > 0 ? duration_ns : 0,
  };
  if (!pb_encode(stream, MITERUBY_PPROF_FRAGMENT_PROFILE_FIELDS, &profile))
    return MITERUBY_SERIALIZER_PROFILE_ENCODING_ERROR;
  RETURN_IF_ERROR(flush_if_needed(state));

  // 10. Emit FragmentSample (Does not require GVL, depends: 2)
  for (size_t pos = 0; pos < interned_events_pos;) {
    const miteruby_event_deduped_sample_t *event = (const miteruby_event_deduped_sample_t *)(interned_events_queue + pos);
    miteruby_stack_t stack = miteruby_stack_dedup_get(interned_events_queue, event->stack_id);
    uint8_t stack_status = event->header.flags & MITERUBY_EVENT_STACK_STATUS_MASK;
    bool unavailable = stack_status == MITERUBY_EVENT_STACK_UNAVAILABLE || stack.frame_count == 0;
    size_t frame_offset = (event->header.flags & MITERUBY_EVENT_FROM_SIGNAL_HANDLER) ? 1 : 0;
    size_t location_count = (unavailable ? 1 : stack.frame_count) + frame_offset + 1;
    uint64_t location_ids[location_count];
    location_ids[location_count - 1] = PPROF_LOCATION_ROOT;
    if (frame_offset != 0) location_ids[0] = PPROF_LOCATION_SIGHANDLER;
    if (unavailable) {
      location_ids[frame_offset] = PPROF_LOCATION_NATIVE;
    } else {
      RETURN_IF_ERROR(read_location_ids(stack, location_ids + frame_offset));
      if (stack_status == MITERUBY_EVENT_STACK_TRUNCATED) location_ids[frame_offset] = PPROF_LOCATION_TRUNCATED;
    }
    serializer_thread_context *context;
    RETURN_IF_ERROR(thread_context_for(&state->thread_contexts, event->thread.value, &context));
    miteruby_sample_values values = sample_values_for(context, event);
    int64_t end_timestamp_ns = monotonic_to_system_epoch_ns(&time_converter, event->header.timestamp.ns);
    RETURN_IF_ERROR(emit_sample_fragment(stream, location_ids, location_count, values, context, end_timestamp_ns));
    RETURN_IF_ERROR(flush_if_needed(state));
    pos += event->header.size_bytes;
  }
  return compress_buffer(state, ZSTD_e_end);
}

static VALUE native_serialize(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  if (!state->compression_finished) rb_raise(rb_eRuntimeError, "Streaming profile must be prepared before serialization");
  VALUE bytes_string = rb_str_new((const char *)state->compressed_serialization_buffer, state->compressed_serialization_size);

  VALUE start = rb_time_nano_new(state->start_time_ns / SECONDS_AS_NS(1), state->start_time_ns % SECONDS_AS_NS(1));
  VALUE finish = rb_time_nano_new(state->finish_time_ns / SECONDS_AS_NS(1), state->finish_time_ns % SECONDS_AS_NS(1));

  VALUE result = rb_funcall(rb_path2class("Datadog::Profiling::EncodedProfile"), rb_intern("from_custom"), 3, start, finish, bytes_string);
  result = rb_ary_new_from_args(4, start, finish, result, rb_hash_new());
  state->start_time_ns = state->finish_time_ns;
  RB_GC_GUARD(serializer);
  return result;
}

static VALUE native_reset_after_fork(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  state->compressed_serialization_size = 0;
  state->compression_finished = false;
  state->start_time_ns = system_epoch_time_now_ns();
  state->finish_time_ns = state->start_time_ns;
  return Qtrue;
}

static VALUE native_stats(DDTRACE_UNUSED VALUE klass, DDTRACE_UNUSED VALUE serializer) {
  return rb_hash_new();
}

void miteruby_serializer_init(VALUE profiling_module) {
  VALUE miteruby = rb_define_module_under(profiling_module, "Miteruby");
  VALUE klass = rb_define_class_under(miteruby, "Serializer", rb_cObject);
  rb_define_alloc_func(klass, serializer_new);
  rb_define_singleton_method(klass, "_native_serialize", native_serialize, 1);
  rb_define_singleton_method(klass, "_native_reset_after_fork", native_reset_after_fork, 1);
  rb_define_singleton_method(klass, "_native_stats", native_stats, 1);
}
