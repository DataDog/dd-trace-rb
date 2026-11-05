#include "streaming_serializer.h"
#include "allocator.h"
#include "stack_dedup.h"
#include "pprof/pb_encode.h"
#include "pprof/pprof_fragments.pb.h"
#include "pprof/zstd.h"
#include "../datadog_ruby_common.h"
#include "../helpers.h"
#include "../time_helpers.h"

#include <string.h>

enum { COMPRESSION_LEVEL = 1 };

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
  // TODO: This can probably be max-sized better given limits on stack depth, etc
  uint8_t *uncompressed_serialization_buffer;
  size_t uncompressed_serialization_size;
  ZSTD_CCtx *compression_context;
  long start_time_ns;
  long finish_time_ns;
  uint64_t recorded_samples;
} streaming_serializer_state;

static void serializer_free(void *data) {
  streaming_serializer_state *state = data;
  miteruby_allocator_free(state->uncompressed_serialization_buffer);
  miteruby_allocator_free(state->compression_context);
  ruby_xfree(state);
}

static size_t serializer_size(const void *data) {
  const streaming_serializer_state *state = data;
  return state ? sizeof(*state) + miteruby_allocator_alloc_size(state->uncompressed_serialization_buffer) +
    miteruby_allocator_alloc_size(state->compression_context) : 0;
}

static const rb_data_type_t serializer_type = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::StreamingSerializer",
  .function = {.dfree = serializer_free, .dsize = serializer_size},
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static streaming_serializer_state *get_state(VALUE serializer) {
  streaming_serializer_state *state;
  TypedData_Get_Struct(serializer, streaming_serializer_state, &serializer_type, state);
  return state;
}

static VALUE serializer_new(VALUE klass) {
  streaming_serializer_state *state;
  VALUE serializer = TypedData_Make_Struct(klass, streaming_serializer_state, &serializer_type, state);
  state->uncompressed_serialization_buffer = miteruby_allocator_alloc(MiB_AS_BYTES(100), "uncompressed_serialization_buffer");
  if (state->uncompressed_serialization_buffer == NULL)
    rb_raise(rb_eRuntimeError, "Failed to allocate miteruby.uncompressed_serialization_buffer");
  state->start_time_ns = system_epoch_time_now_ns();
  state->finish_time_ns = state->start_time_ns;
  return serializer;
}

static void record_stack_sample(
  streaming_serializer_state *state, DDTRACE_UNUSED const miteruby_event_deduped_sample_t *event, DDTRACE_UNUSED miteruby_stack_t stack
) {
  state->recorded_samples++;
}

// After the fixed strings, each zero-based function ID from the CME/ISEQ map reserves two
// consecutive strings: name, then filename. These pairs must be emitted in map-ID order.
/*
static int64_t string_table_id_for(uint64_t function_id) {
  return PPROF_STRING_TIMELINE + 1 + function_id * 2;
}
*/

static void emit_string_table_entry(pb_ostream_t *stream, const char *string, size_t length) {
  if (!pb_encode_tag(stream, PB_WT_STRING, MITERUBY_PPROF_FRAGMENT_STRING_TABLE_STRING_TABLE_TAG) ||
      !pb_encode_string(stream, (const pb_byte_t *) string, length))
    rb_raise(rb_eRuntimeError, "Failed to encode streaming string table: %s", PB_GET_ERROR(stream));
}

void miteruby_streaming_serializer_prepare_serialize(VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos) {
  streaming_serializer_state *state = get_state(serializer);
  state->uncompressed_serialization_size = 0;
  long finish_time_ns = system_epoch_time_now_ns();

  pb_ostream_t stream = pb_ostream_from_buffer(
    state->uncompressed_serialization_buffer, miteruby_allocator_alloc_size(state->uncompressed_serialization_buffer)
  );

  // Emit FragmentSampleType
  for (size_t i = 0; i < sizeof(sample_types) / sizeof(sample_types[0]); i++) {
    miteruby_pprof_fragment_sample_type_t fragment = {.has_sample_type = true, .sample_type = sample_types[i]};
    if (!pb_encode(&stream, MITERUBY_PPROF_FRAGMENT_SAMPLE_TYPE_FIELDS, &fragment))
      rb_raise(rb_eRuntimeError, "Failed to encode streaming sample type: %s", PB_GET_ERROR(&stream));
  }

  // Emit FragmentFunction
  /*
  for (
    verstable_mark_cme_iseq_map_itr entry = verstable_mark_cme_iseq_map_first(mark_cme_iseq_map);
    !verstable_mark_cme_iseq_map_is_end(entry);
    entry = verstable_mark_cme_iseq_map_next(entry)
  ) {
    uint64_t map_id = entry.data->val.value;
    int64_t name_id = string_table_id_for(map_id);
    miteruby_pprof_fragment_function_t fragment = {
      .has_function = true,
      .function = {.id = map_id + 1, .name = name_id, .filename = name_id + 1},
    };
    if (!pb_encode(&stream, MITERUBY_PPROF_FRAGMENT_FUNCTION_FIELDS, &fragment))
      rb_raise(rb_eRuntimeError, "Failed to encode streaming function: %s", PB_GET_ERROR(&stream));
  }
  */

  // Emit FragmentStringTable
  for (size_t i = 0; i < sizeof(fixed_string_values) / sizeof(fixed_string_values[0]); i++) {
    const char *string = fixed_string_values[i];
    emit_string_table_entry(&stream, string, strlen(string));
  }

  // Emit FragmentProfile
  int64_t duration_ns = finish_time_ns - state->start_time_ns;
  miteruby_pprof_fragment_profile_t profile = {
    .time_nanos = state->start_time_ns,
    .duration_nanos = duration_ns > 0 ? duration_ns : 0,
  };
  if (!pb_encode(&stream, MITERUBY_PPROF_FRAGMENT_PROFILE_FIELDS, &profile))
    rb_raise(rb_eRuntimeError, "Failed to encode streaming profile metadata: %s", PB_GET_ERROR(&stream));

  state->uncompressed_serialization_size = stream.bytes_written;
  state->finish_time_ns = finish_time_ns;

  for (size_t pos = 0; pos < interned_events_pos;) {
    const miteruby_event_deduped_sample_t *event = (const miteruby_event_deduped_sample_t *)(interned_events_queue + pos);
    miteruby_stack_t stack = miteruby_stack_dedup_get(interned_events_queue, event->stack_id);
    record_stack_sample(state, event, stack);
    pos += event->header.size_bytes;
  }
}

static VALUE native_serialize(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  streaming_serializer_state *state = get_state(serializer);
  long finish_time_ns = state->finish_time_ns;
  size_t capacity = ZSTD_compressBound(state->uncompressed_serialization_size);
  if (ZSTD_isError(capacity)) rb_raise(rb_eRuntimeError, "Failed to size zstd buffer: %s", ZSTD_getErrorName(capacity));
  VALUE bytes_string = rb_str_new(NULL, capacity);
  if (state->compression_context == NULL) {
    size_t workspace_size = ZSTD_estimateCStreamSize(COMPRESSION_LEVEL);
    if (ZSTD_isError(workspace_size)) rb_raise(rb_eRuntimeError, "Failed to size zstd workspace: %s", ZSTD_getErrorName(workspace_size));
    void *workspace = miteruby_allocator_alloc(workspace_size, "streaming_serializer_zstd");
    if (workspace == NULL) rb_memerror();
    state->compression_context = ZSTD_initStaticCCtx(workspace, workspace_size);
    if (state->compression_context == NULL) {
      miteruby_allocator_free(workspace);
      rb_raise(rb_eRuntimeError, "Failed to initialize static zstd context");
    }
  }
  size_t compressed_size = ZSTD_compressCCtx(
    state->compression_context, RSTRING_PTR(bytes_string), capacity,
    state->uncompressed_serialization_buffer, state->uncompressed_serialization_size, COMPRESSION_LEVEL
  );
  if (ZSTD_isError(compressed_size)) rb_raise(rb_eRuntimeError, "Failed to compress streaming profile: %s", ZSTD_getErrorName(compressed_size));
  rb_str_resize(bytes_string, compressed_size);
  VALUE start = rb_time_nano_new(state->start_time_ns / SECONDS_AS_NS(1), state->start_time_ns % SECONDS_AS_NS(1));
  VALUE finish = rb_time_nano_new(finish_time_ns / SECONDS_AS_NS(1), finish_time_ns % SECONDS_AS_NS(1));
  VALUE result = rb_funcall(rb_path2class("Datadog::Profiling::EncodedProfile"), rb_intern("from_custom"), 3, start, finish, bytes_string);
  state->start_time_ns = finish_time_ns;
  RB_GC_GUARD(serializer);
  RB_GC_GUARD(bytes_string);
  return result;
}

static VALUE native_reset_after_fork(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  streaming_serializer_state *state = get_state(serializer);
  state->recorded_samples = 0;
  state->uncompressed_serialization_size = 0;
  state->start_time_ns = system_epoch_time_now_ns();
  state->finish_time_ns = state->start_time_ns;
  return Qtrue;
}

static VALUE native_stats(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  uint64_t recorded_samples = get_state(serializer)->recorded_samples;
  VALUE stats = rb_hash_new();
  rb_hash_aset(stats, ID2SYM(rb_intern("recorded_samples")), ULL2NUM(recorded_samples));
  return stats;
}

void miteruby_streaming_serializer_init(VALUE profiling_module) {
  VALUE miteruby = rb_define_module_under(profiling_module, "Miteruby");
  VALUE klass = rb_define_class_under(miteruby, "StreamingSerializer", rb_cObject);
  rb_define_alloc_func(klass, serializer_new);
  rb_define_singleton_method(klass, "_native_serialize", native_serialize, 1);
  rb_define_singleton_method(klass, "_native_reset_after_fork", native_reset_after_fork, 1);
  rb_define_singleton_method(klass, "_native_stats", native_stats, 1);
}
