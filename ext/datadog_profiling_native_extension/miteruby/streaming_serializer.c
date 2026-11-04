#include "streaming_serializer.h"
#include "allocator.h"
#include "stack_dedup.h"
#include "../datadog_ruby_common.h"
#include "../helpers.h"

typedef struct {
  // TODO: This can probably be max-sized better given limits on stack depth, etc
  uint8_t *uncompressed_serialization_buffer;
  uint64_t recorded_samples;
} streaming_serializer_state;

static void serializer_free(void *data) {
  streaming_serializer_state *state = data;
  miteruby_allocator_free(state->uncompressed_serialization_buffer);
  ruby_xfree(state);
}

static size_t serializer_size(const void *data) {
  const streaming_serializer_state *state = data;
  return state ? sizeof(*state) + miteruby_allocator_alloc_size(state->uncompressed_serialization_buffer) : 0;
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
  return serializer;
}

static void record_stack_sample(
  streaming_serializer_state *state, DDTRACE_UNUSED const miteruby_event_deduped_sample_t *event, DDTRACE_UNUSED miteruby_stack_t stack
) {
  state->recorded_samples++;
}

void miteruby_streaming_serializer_prepare_serialize(VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos) {
  streaming_serializer_state *state = get_state(serializer);

  for (size_t pos = 0; pos < interned_events_pos;) {
    const miteruby_event_deduped_sample_t *event = (const miteruby_event_deduped_sample_t *)(interned_events_queue + pos);
    miteruby_stack_t stack = miteruby_stack_dedup_get(interned_events_queue, event->stack_id);
    record_stack_sample(state, event, stack);
    pos += event->header.size_bytes;
  }
}

static VALUE native_serialize(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  get_state(serializer);
  return Qnil;
}

static VALUE native_reset_after_fork(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  get_state(serializer)->recorded_samples = 0;
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
