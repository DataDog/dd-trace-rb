#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"
#include <stdbool.h>
#include <ruby.h>

static bool fail_allocations;
static bool fail_string_allocation;

static void *test_allocator_alloc(size_t size, const char *name) {
  return fail_allocations ? NULL : miteruby_allocator_alloc(size, name);
}

static VALUE test_str_new(const char *bytes, long size) {
  if (fail_string_allocation) rb_raise(rb_eRuntimeError, "String allocation failed");
  return rb_str_new(bytes, size);
}

#undef rb_str_new
#define rb_str_new test_str_new
#define miteruby_allocator_alloc test_allocator_alloc
#include "../../../ext/datadog_profiling_native_extension/miteruby/serializer.c"
#undef miteruby_allocator_alloc
#undef rb_str_new

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

static VALUE prepare_with_exception(VALUE prepare_state_value) {
  miteruby_serializer_prepare_serialization_state_t *prepare_state = (miteruby_serializer_prepare_serialization_state_t *)prepare_state_value;
  miteruby_serializer_persistent_state_t *state = prepare_state->persistent_state;
  assert(initialize_compression(state) == MITERUBY_SERIALIZER_OK);
  serializer_thread_context *context;
  assert(thread_context_for(&state->thread_contexts, INT2FIX(0), &context) == MITERUBY_SERIALIZER_OK);
  rb_raise(rb_eRuntimeError, "Interrupted preparation");
}

static VALUE prepare_with_exception_and_cleanup(VALUE prepare_state_value) {
  miteruby_serializer_prepare_serialization_state_t *prepare_state = (miteruby_serializer_prepare_serialization_state_t *)prepare_state_value;
  return rb_ensure(prepare_with_exception, prepare_state_value, prepare_serialize_cleanup, (VALUE)prepare_state->persistent_state);
}

static void test_preparation_cleanup(void) {
  enum { SUCCESS, BUFFER_FULL, RUBY_EXCEPTION, REUSE_AFTER_EXCEPTION };
  uint8_t *input = miteruby_allocator_alloc(1024, "test_input");
  assert(input != NULL);
  size_t persistent_bytes = miteruby_allocator_requested_bytes();
  miteruby_serializer_persistent_state_t *state = ruby_xcalloc(1, sizeof(*state));
  state->uncompressed_serialization_buffer = input;
  verstable_serializer_thread_contexts_map_init(&state->thread_contexts);
  state->compression_workspace = miteruby_allocator_alloc(ZSTD_estimateCStreamSize(COMPRESSION_LEVEL), "serializer_zstd");
  void *workspace = state->compression_workspace;
  assert(workspace != NULL);

  for (int scenario = SUCCESS; scenario <= REUSE_AFTER_EXCEPTION; scenario++) {
    miteruby_allocator_free(state->compressed_serialization_buffer);
    state->compressed_serialization_buffer = miteruby_allocator_alloc(1024, "test_output");
    assert(state->compressed_serialization_buffer != NULL);
    miteruby_allocator_free(state->interned_events_queue);
    state->interned_events_queue = miteruby_allocator_alloc(1024, "test_queue");
    assert(state->interned_events_queue != NULL);
    assert(serializer_size(state) == sizeof(*state) + miteruby_allocator_requested_bytes());
    state->status = SERIALIZER_WORKING;
    state->compressed_serialization_size = scenario == BUFFER_FULL ? 1023 : 0;
    state->stream = pb_ostream_from_buffer(input, 1024);
    miteruby_serializer_prepare_serialization_state_t prepare_state = {
      .persistent_state = state,
    };
    verstable_serializer_thread_contexts_map_clear(&state->thread_contexts);
    if (scenario == RUBY_EXCEPTION) {
      int error = 0;
      rb_protect(prepare_with_exception_and_cleanup, (VALUE)&prepare_state, &error);
      assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
      rb_set_errinfo(Qnil);
    } else {
      fail_allocations = scenario == REUSE_AFTER_EXCEPTION;
      miteruby_serializer_exit_reason_t reason = initialize_compression(state);
      assert(reason == MITERUBY_SERIALIZER_OK);
      serializer_thread_context *context;
      assert(thread_context_for(&state->thread_contexts, INT2FIX(0), &context) == MITERUBY_SERIALIZER_OK);
      assert(pb_write(&state->stream, (const pb_byte_t *)"profile", 7));
      reason = compress_buffer(state, ZSTD_e_end);
      assert(reason == (scenario == BUFFER_FULL ? MITERUBY_SERIALIZER_COMPRESSED_BUFFER_FULL : MITERUBY_SERIALIZER_OK));
      if (reason == MITERUBY_SERIALIZER_OK) {
        assert(state->compressed_serialization_size > 0);
      }
      fail_allocations = false;
      prepare_serialize_cleanup((VALUE)state);
    }
    if (scenario == SUCCESS) {
      persistent_bytes = miteruby_allocator_requested_bytes();
    }
    assert(state->compression_workspace == workspace);
    assert(miteruby_allocator_requested_bytes() == persistent_bytes);
    assert(serializer_size(state) == sizeof(*state) + persistent_bytes);
    assert(state->status == SERIALIZER_EMPTY);
    assert(state->interned_events_queue != NULL);
    assert(miteruby_allocator_alloc_size(input) == 1024);
    assert(miteruby_allocator_alloc_size(state->compressed_serialization_buffer) == 1024);
  }
  assert(state->interned_events_queue != NULL);
  serializer_free(state);
  assert(miteruby_allocator_requested_bytes() == 0);
}

static VALUE serialize_working_profile(VALUE serializer) {
  return native_serialize(Qnil, serializer);
}

static VALUE check_available(VALUE serializer) {
  miteruby_serializer_check_available(serializer);
  return Qnil;
}

static void test_working_status(void) {
  VALUE serializer = serializer_new(rb_cObject);
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  assert(state->compression_workspace != NULL);
  assert(miteruby_allocator_alloc_size(state->compression_workspace) == ZSTD_estimateCStreamSize(COMPRESSION_LEVEL));
  assert(state->status == SERIALIZER_EMPTY);
  assert(state->compressed_serialization_buffer != NULL);
  miteruby_serializer_check_available(serializer);
  state->status = SERIALIZER_WORKING;
  uint8_t *queue = miteruby_allocator_alloc(1024, "test_queue");
  assert(queue != NULL);
  assert(miteruby_serializer_prepare_serialize(serializer, queue, 0, NULL, NULL, NULL) == MITERUBY_SERIALIZER_ALREADY_WORKING);
  assert(queue != NULL && state->interned_events_queue == NULL);
  int error = 0;
  rb_protect(check_available, serializer, &error);
  assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
  assert(state->status == SERIALIZER_WORKING);
  rb_set_errinfo(Qnil);
  rb_protect(serialize_working_profile, serializer, &error);
  assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
  assert(state->status == SERIALIZER_WORKING);
  rb_set_errinfo(Qnil);

  state->compressed_serialization_size = 123;
  state->start_time_ns = 0;
  state->finish_time_ns = 0;
  state->interned_events_queue = queue;
  assert(state->compressed_serialization_buffer != NULL);
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  assert(native_reset_after_fork(Qnil, serializer) == Qtrue);
  assert(state->interned_events_queue == NULL);
  assert(state->compressed_serialization_buffer != NULL);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes - 1024);
  assert(state->status == SERIALIZER_EMPTY);
  miteruby_serializer_check_available(serializer);
  assert(state->compressed_serialization_size == 0);
  assert(state->start_time_ns > 0);
  assert(state->finish_time_ns == state->start_time_ns);

  miteruby_mark_frame_array_t frames = {0};
  miteruby_location_array_t locations = {0};
  verstable_mark_threads_set threads;
  verstable_mark_threads_set_init(&threads);
  queue = miteruby_allocator_alloc(1024, "test_queue");
  assert(queue != NULL);
  assert(miteruby_serializer_prepare_serialize(serializer, queue, 0, &frames, &locations, &threads) == MITERUBY_SERIALIZER_OK);
  assert(state->interned_events_queue == NULL);
  assert(state->status == SERIALIZER_FINISHED);
  assert(miteruby_allocator_alloc_size(state->compressed_serialization_buffer) == MAX_COMPRESSED_BUFFER_BYTES);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes - 1024);
  assert(native_reset_after_fork(Qnil, serializer) == Qtrue);
  assert(state->compressed_serialization_buffer != NULL);
  assert(state->status == SERIALIZER_EMPTY);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes - 1024);
  verstable_mark_threads_set_cleanup(&threads);
  RB_GC_GUARD(serializer);
}

static VALUE prepare_empty_profile(VALUE serializer) {
  miteruby_mark_frame_array_t frames = {0};
  miteruby_location_array_t locations = {0};
  verstable_mark_threads_set threads;
  verstable_mark_threads_set_init(&threads);
  uint8_t *queue = miteruby_allocator_alloc(1024, "test_queue");
  assert(queue != NULL);
  assert(miteruby_serializer_prepare_serialize(serializer, queue, 0, &frames, &locations, &threads) == MITERUBY_SERIALIZER_OK);
  verstable_mark_threads_set_cleanup(&threads);
  return Qnil;
}

static VALUE profile_from_custom(VALUE klass, VALUE start, VALUE finish, VALUE bytes) {
  return bytes;
}

static void test_compressed_buffer_lifecycle(void) {
  VALUE serializer = serializer_new(rb_cObject);
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  size_t idle_bytes = miteruby_allocator_requested_bytes();
  assert(state->compressed_serialization_buffer != NULL);

  for (int cycle = 0; cycle < 2; cycle++) {
    prepare_empty_profile(serializer);
    assert(miteruby_allocator_requested_bytes() == idle_bytes);
    prepare_empty_profile(serializer);
    assert(miteruby_allocator_requested_bytes() == idle_bytes);
    uint8_t *previous_buffer = state->compressed_serialization_buffer;
    VALUE result = native_serialize(Qnil, serializer);
    assert(state->compressed_serialization_buffer != previous_buffer);
    assert(state->compressed_serialization_buffer[0] == 0);
    assert(RSTRING_LEN(rb_ary_entry(result, 2)) > 0);
    assert(state->status == SERIALIZER_EMPTY);
    assert(state->compressed_serialization_buffer != NULL);
    assert(state->compressed_serialization_size == 0);
    assert(miteruby_allocator_requested_bytes() == idle_bytes);
  }

  prepare_empty_profile(serializer);
  uint8_t *previous_buffer = state->compressed_serialization_buffer;
  size_t previous_size = state->compressed_serialization_size;
  fail_string_allocation = true;
  int error = 0;
  rb_protect(serialize_working_profile, serializer, &error);
  fail_string_allocation = false;
  assert(error != 0);
  rb_set_errinfo(Qnil);
  assert(state->status == SERIALIZER_EMPTY);
  assert(state->compressed_serialization_buffer == previous_buffer);
  assert(state->compressed_serialization_size == previous_size);
  assert(miteruby_allocator_requested_bytes() == idle_bytes);

  prepare_empty_profile(serializer);
  previous_buffer = state->compressed_serialization_buffer;
  fail_allocations = true;
  rb_protect(serialize_working_profile, serializer, &error);
  fail_allocations = false;
  assert(state->compressed_serialization_buffer == previous_buffer);
  assert(state->compressed_serialization_size == 0);
  assert(error != 0);
  rb_set_errinfo(Qnil);
  assert(state->status == SERIALIZER_EMPTY);
  assert(state->interned_events_queue == NULL);
  assert(state->compressed_serialization_buffer != NULL);
  assert(miteruby_allocator_requested_bytes() == idle_bytes);
  prepare_empty_profile(serializer);
  native_serialize(Qnil, serializer);
  assert(miteruby_allocator_requested_bytes() == idle_bytes);

  state->interned_events_queue = miteruby_allocator_alloc(1024, "test_queue");
  assert(state->interned_events_queue != NULL);
  state->status = SERIALIZER_WORKING;
  miteruby_serializer_prepare_serialization_state_t prepare_state = {.persistent_state = state};
  rb_protect(prepare_with_exception_and_cleanup, (VALUE)&prepare_state, &error);
  assert(error != 0);
  rb_set_errinfo(Qnil);
  assert(state->status == SERIALIZER_EMPTY);
  assert(state->interned_events_queue != NULL);
  size_t bytes_with_leftover_queue = miteruby_allocator_requested_bytes();
  prepare_empty_profile(serializer);
  assert(state->interned_events_queue == NULL);
  assert(miteruby_allocator_requested_bytes() == bytes_with_leftover_queue - 1024);
  native_serialize(Qnil, serializer);
  RB_GC_GUARD(serializer);
}

int main(int argc, char **argv) {
  ruby_sysinit(&argc, &argv);
  RUBY_INIT_STACK;
  ruby_init();
  VALUE datadog = rb_define_module("Datadog");
  VALUE profiling = rb_define_module_under(datadog, "Profiling");
  VALUE encoded_profile = rb_define_class_under(profiling, "EncodedProfile", rb_cObject);
  rb_define_singleton_method(encoded_profile, "from_custom", profile_from_custom, 3);
  test_sample_values();
  test_reuse_after_error();
  test_preparation_cleanup();
  test_working_status();
  test_compressed_buffer_lifecycle();
  puts("Miteruby serializer tests passed");
  return ruby_cleanup(0);
}
