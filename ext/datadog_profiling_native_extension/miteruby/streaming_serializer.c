#include "streaming_serializer.h"
#include "../datadog_ruby_common.h"

typedef struct {
  uint64_t recorded_samples;
} streaming_serializer_state;

static size_t serializer_size(const void *data) {
  return data ? sizeof(streaming_serializer_state) : 0;
}

static const rb_data_type_t serializer_type = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::StreamingSerializer",
  .function = {.dfree = RUBY_DEFAULT_FREE, .dsize = serializer_size},
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static streaming_serializer_state *get_state(VALUE serializer) {
  streaming_serializer_state *state;
  TypedData_Get_Struct(serializer, streaming_serializer_state, &serializer_type, state);
  return state;
}

static VALUE serializer_new(VALUE klass) {
  streaming_serializer_state *state;
  return TypedData_Make_Struct(klass, streaming_serializer_state, &serializer_type, state);
}

void miteruby_streaming_serializer_record_stack_sample(
  VALUE serializer, DDTRACE_UNUSED const miteruby_event_deduped_sample_t *event, DDTRACE_UNUSED miteruby_stack_t stack
) {
  get_state(serializer)->recorded_samples++;
}

static VALUE native_serialize(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  get_state(serializer);
  return Qnil;
}

static VALUE native_reset_after_fork(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  *get_state(serializer) = (streaming_serializer_state) {0};
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
