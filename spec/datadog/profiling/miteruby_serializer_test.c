#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"
#include <stdbool.h>

static bool fail_allocations;

static void *test_allocator_alloc(size_t size, const char *name) {
  return fail_allocations ? NULL : miteruby_allocator_alloc(size, name);
}

#define miteruby_allocator_alloc test_allocator_alloc
#include "../../../ext/datadog_profiling_native_extension/miteruby/serializer.c"
#undef miteruby_allocator_alloc

#undef NDEBUG
#include <assert.h>

static void test_sample_values(void) {
  verstable_serializer_thread_contexts_map contexts;
  const struct {
    int thread;
    long cpu, monotonic, expected_cpu, expected_wall;
  } samples[] = {
    {1, -1, 100, 0, 0},
    {2, 50, 110, 0, 0},
    {1, 0, 120, 0, 20},
    {1, 100, 150, 100, 30},
    {2, 80, 160, 30, 50},
    {1, -1, 180, 0, 30},
    {1, 180, 200, 80, 20},
  };

  verstable_serializer_thread_contexts_map_init(&contexts);
  size_t allocated_bytes = 0;
  for (int serialization = 0; serialization < 2; serialization++) {
    verstable_serializer_thread_contexts_map_clear(&contexts);
    if (serialization == 1) {
      for (int thread = 1; thread <= 2; thread++) {
        serializer_thread_context *context;
        assert(thread_context_for(&contexts, INT2FIX(thread), &context) == MITERUBY_SERIALIZER_OK);
        context->thread_name_string_id = 22 + thread * 2;
        context->thread_id_string_id = context->thread_name_string_id + 1;
        assert(!context->has_previous_sample);
      }
    }
    for (size_t i = 0; i < sizeof(samples) / sizeof(samples[0]); i++) {
      miteruby_event_deduped_sample_t event = {
        .header = {.cpu_time = {.ns = samples[i].cpu}, .timestamp = {.ns = samples[i].monotonic}},
      };
      serializer_thread_context *context;
      assert(thread_context_for(&contexts, INT2FIX(samples[i].thread), &context) == MITERUBY_SERIALIZER_OK);
      miteruby_sample_values values = sample_values_for(context, &event);
      assert(values.cpu_time_ns == samples[i].expected_cpu);
      assert(values.wall_time_ns == samples[i].expected_wall);
      assert(values.cpu_or_wall_samples == 1);
      assert(values.alloc_samples == 0 && values.alloc_samples_unscaled == 0 && values.timeline_wall_time_ns == 0);
      assert(context->has_previous_sample);
      if (serialization == 1) {
        assert(context->thread_name_string_id == 22 + samples[i].thread * 2);
        assert(context->thread_id_string_id == context->thread_name_string_id + 1);
      }
    }
    assert(verstable_serializer_thread_contexts_map_size(&contexts) == 2);
    if (serialization == 0) allocated_bytes = miteruby_allocator_requested_bytes();
    else assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  }
  verstable_serializer_thread_contexts_map_cleanup(&contexts);
  assert(miteruby_allocator_requested_bytes() == 0);
}

static void test_reuse_after_error(void) {
  verstable_serializer_thread_contexts_map contexts;
  verstable_serializer_thread_contexts_map_init(&contexts);
  serializer_thread_context *context;
  assert(thread_context_for(&contexts, INT2FIX(0), &context) == MITERUBY_SERIALIZER_OK);
  fail_allocations = true;
  miteruby_serializer_exit_reason_t reason = MITERUBY_SERIALIZER_OK;
  for (int i = 1; i < 100 && reason == MITERUBY_SERIALIZER_OK; i++) {
    reason = thread_context_for(&contexts, INT2FIX(i), &context);
  }
  assert(reason == MITERUBY_SERIALIZER_THREAD_CONTEXTS_FULL);
  assert(verstable_serializer_thread_contexts_map_size(&contexts) > 0);
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  verstable_serializer_thread_contexts_map_clear(&contexts);
  miteruby_event_deduped_sample_t event = {.header = {.cpu_time = {.ns = 100}, .timestamp = {.ns = 200}}};
  assert(thread_context_for(&contexts, INT2FIX(0), &context) == MITERUBY_SERIALIZER_OK);
  miteruby_sample_values values = sample_values_for(context, &event);
  assert(values.cpu_time_ns == 0 && values.wall_time_ns == 0);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  fail_allocations = false;
  verstable_serializer_thread_contexts_map_cleanup(&contexts);
  assert(miteruby_allocator_requested_bytes() == 0);
}

static VALUE prepare_with_exception(VALUE state_value) {
  miteruby_serializer_prepare_serialization_state_t *state = (miteruby_serializer_prepare_serialization_state_t *)state_value;
  assert(initialize_compression(state) == MITERUBY_SERIALIZER_OK);
  serializer_thread_context *context;
  assert(thread_context_for(&state->persistent_state->thread_contexts, INT2FIX(0), &context) == MITERUBY_SERIALIZER_OK);
  rb_raise(rb_eRuntimeError, "Interrupted preparation");
}

static VALUE prepare_with_exception_and_cleanup(VALUE state_value) {
  return rb_ensure(prepare_with_exception, state_value, prepare_serialize_cleanup, state_value);
}

static void test_preparation_cleanup(void) {
  enum { SUCCESS, BUFFER_FULL, RUBY_EXCEPTION, REUSE_AFTER_EXCEPTION };
  uint8_t *input = miteruby_allocator_alloc(1024, "test_input");
  uint8_t *output = miteruby_allocator_alloc(1024, "test_output");
  assert(input != NULL && output != NULL);
  size_t persistent_bytes = miteruby_allocator_requested_bytes();
  miteruby_serializer_persistent_state_t *persistent_state = ruby_xcalloc(1, sizeof(*persistent_state));
  persistent_state->uncompressed_serialization_buffer = input;
  persistent_state->compressed_serialization_buffer = output;
  verstable_serializer_thread_contexts_map_init(&persistent_state->thread_contexts);
  persistent_state->compression_workspace = miteruby_allocator_alloc(ZSTD_estimateCStreamSize(COMPRESSION_LEVEL), "serializer_zstd");
  void *workspace = persistent_state->compression_workspace;
  assert(workspace != NULL);

  for (int scenario = SUCCESS; scenario <= REUSE_AFTER_EXCEPTION; scenario++) {
    persistent_state->status = SERIALIZER_WORKING;
    miteruby_serializer_prepare_serialization_state_t state = {
      .persistent_state = persistent_state,
      .stream = pb_ostream_from_buffer(input, 1024),
      .compressed_buffer = {.dst = output, .size = scenario == BUFFER_FULL ? 1 : 1024},
    };
    verstable_serializer_thread_contexts_map_clear(&persistent_state->thread_contexts);
    if (scenario == RUBY_EXCEPTION) {
      int error = 0;
      rb_protect(prepare_with_exception_and_cleanup, (VALUE)&state, &error);
      assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
      rb_set_errinfo(Qnil);
    } else {
      fail_allocations = scenario == REUSE_AFTER_EXCEPTION;
      miteruby_serializer_exit_reason_t reason = initialize_compression(&state);
      assert(reason == MITERUBY_SERIALIZER_OK);
      serializer_thread_context *context;
      assert(thread_context_for(&persistent_state->thread_contexts, INT2FIX(0), &context) == MITERUBY_SERIALIZER_OK);
      assert(pb_write(&state.stream, (const pb_byte_t *)"profile", 7));
      reason = compress_buffer(&state, ZSTD_e_end);
      assert(reason == (scenario == BUFFER_FULL ? MITERUBY_SERIALIZER_COMPRESSED_BUFFER_FULL : MITERUBY_SERIALIZER_OK));
      fail_allocations = false;
      prepare_serialize_cleanup((VALUE)&state);
    }
    if (scenario == SUCCESS) {
      persistent_bytes = miteruby_allocator_requested_bytes();
    }
    assert(persistent_state->compression_workspace == workspace);
    assert(miteruby_allocator_requested_bytes() == persistent_bytes);
    assert(serializer_size(persistent_state) == sizeof(*persistent_state) + persistent_bytes);
    assert(persistent_state->status == SERIALIZER_EMPTY);
    assert(miteruby_allocator_alloc_size(input) == 1024);
    assert(miteruby_allocator_alloc_size(output) == 1024);
  }
  serializer_free(persistent_state);
  assert(miteruby_allocator_requested_bytes() == 0);
}

static VALUE serialize_working_profile(VALUE serializer) {
  return native_serialize(Qnil, serializer);
}

static VALUE reset_working_profile(VALUE serializer) {
  return native_reset_after_fork(Qnil, serializer);
}

static void test_working_status(void) {
  VALUE serializer = serializer_new(rb_cObject);
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  assert(state->compression_workspace != NULL);
  assert(miteruby_allocator_alloc_size(state->compression_workspace) == ZSTD_estimateCStreamSize(COMPRESSION_LEVEL));
  assert(state->status == SERIALIZER_EMPTY);
  assert(!miteruby_serializer_is_working(serializer));
  assert(!miteruby_serializer_is_working(Qnil));
  state->status = SERIALIZER_WORKING;
  assert(miteruby_serializer_is_working(serializer));
  assert(miteruby_serializer_prepare_serialize(serializer, NULL, 0, NULL, NULL, NULL) == MITERUBY_SERIALIZER_ALREADY_WORKING);
  VALUE (*operations[])(VALUE) = {serialize_working_profile, reset_working_profile};
  for (size_t i = 0; i < sizeof(operations) / sizeof(operations[0]); i++) {
    int error = 0;
    rb_protect(operations[i], serializer, &error);
    assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
    assert(state->status == SERIALIZER_WORKING);
    rb_set_errinfo(Qnil);
  }
  state->status = SERIALIZER_EMPTY;
  RB_GC_GUARD(serializer);
}

int main(int argc, char **argv) {
  ruby_sysinit(&argc, &argv);
  RUBY_INIT_STACK;
  ruby_init();
  test_sample_values();
  test_reuse_after_error();
  test_preparation_cleanup();
  test_working_status();
  puts("Miteruby serializer tests passed");
  return ruby_cleanup(0);
}
