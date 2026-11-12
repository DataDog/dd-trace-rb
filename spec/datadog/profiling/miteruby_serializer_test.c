#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"
#include "../../../ext/datadog_profiling_native_extension/miteruby/pprof/pb_encode.h"
#include "../../../ext/datadog_profiling_native_extension/ruby_helpers.h"
#include <stdbool.h>
#include <ruby.h>
#include <ruby/thread.h>
#include <threads.h>
#include <sys/wait.h>
#include <unistd.h>

#undef NDEBUG
#include <assert.h>

static bool fail_allocations;
static bool fail_string_allocation;
static bool fail_preparation_encoding;
static enum { NO_GATE, GATE_BEFORE, GATE_DURING } no_gvl_mode;
static mtx_t gate_mutex;
static cnd_t gate_condition;
static bool gate_entered, gate_released;

static void *pause_no_gvl(void *unused) {
  assert(!ruby_thread_has_gvl_p());
  assert(mtx_lock(&gate_mutex) == thrd_success);
  gate_entered = true;
  assert(cnd_broadcast(&gate_condition) == thrd_success);
  while (!gate_released) assert(cnd_wait(&gate_condition, &gate_mutex) == thrd_success);
  assert(mtx_unlock(&gate_mutex) == thrd_success);
  return NULL;
}

static void *wait_for_no_gvl(void *unused) {
  assert(mtx_lock(&gate_mutex) == thrd_success);
  while (!gate_entered) assert(cnd_wait(&gate_condition, &gate_mutex) == thrd_success);
  assert(mtx_unlock(&gate_mutex) == thrd_success);
  return NULL;
}

static void *test_call_without_gvl(void *(*callback)(void *), void *args, rb_unblock_function_t *ubf, void *ubf_args) {
  // Leave the interruption pending so the real call handles it before starting serialization.
  if (no_gvl_mode == GATE_BEFORE) rb_thread_call_without_gvl2(pause_no_gvl, NULL, ubf, ubf_args);
  return rb_thread_call_without_gvl(callback, args, ubf, ubf_args);
}

static void *test_allocator_alloc(size_t size, const char *name) {
  return fail_allocations ? NULL : miteruby_allocator_alloc(size, name);
}

static VALUE test_str_new(const char *bytes, long size) {
  if (fail_string_allocation) rb_raise(rb_eRuntimeError, "String allocation failed");
  return rb_str_new(bytes, size);
}

static bool test_pb_encode(pb_ostream_t *stream, const pb_msgdesc_t *fields, const void *src_struct) {
  if (fail_preparation_encoding) rb_raise(rb_eRuntimeError, "Interrupted preparation");
  if (no_gvl_mode == GATE_DURING && !ruby_thread_has_gvl_p()) pause_no_gvl(NULL);
  return pb_encode(stream, fields, src_struct);
}

#undef rb_str_new
#define rb_str_new test_str_new
#define miteruby_allocator_alloc test_allocator_alloc
#define pb_encode test_pb_encode
#define rb_thread_call_without_gvl test_call_without_gvl
#include "../../../ext/datadog_profiling_native_extension/miteruby/serializer.c"
#undef rb_thread_call_without_gvl
#undef pb_encode
#undef miteruby_allocator_alloc
#undef rb_str_new

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
        assert(thread_context_for(&contexts, INT2FIX(thread), true, &context) == MITERUBY_SERIALIZER_OK);
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
      assert(thread_context_for(&contexts, INT2FIX(samples[i].thread), serialization == 0, &context) == MITERUBY_SERIALIZER_OK);
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
  assert(thread_context_for(&contexts, INT2FIX(0), true, &context) == MITERUBY_SERIALIZER_OK);
  fail_allocations = true;
  miteruby_serializer_exit_reason_t reason = MITERUBY_SERIALIZER_OK;
  for (int i = 1; i < 100 && reason == MITERUBY_SERIALIZER_OK; i++) {
    reason = thread_context_for(&contexts, INT2FIX(i), true, &context);
  }
  assert(reason == MITERUBY_SERIALIZER_THREAD_CONTEXTS_FULL);
  assert(verstable_serializer_thread_contexts_map_size(&contexts) > 0);
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  verstable_serializer_thread_contexts_map_clear(&contexts);
  miteruby_event_deduped_sample_t event = {.header = {.cpu_time = {.ns = 100}, .timestamp = {.ns = 200}}};
  assert(thread_context_for(&contexts, INT2FIX(0), true, &context) == MITERUBY_SERIALIZER_OK);
  miteruby_sample_values values = sample_values_for(context, &event);
  assert(values.cpu_time_ns == 0 && values.wall_time_ns == 0);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  fail_allocations = false;
  verstable_serializer_thread_contexts_map_cleanup(&contexts);
  assert(miteruby_allocator_requested_bytes() == 0);
}

static VALUE prepare_with_exception(VALUE state_value) {
  miteruby_serializer_persistent_state_t *state = (miteruby_serializer_persistent_state_t *)state_value;
  assert(initialize_compression(state) == MITERUBY_SERIALIZER_OK);
  serializer_thread_context *context;
  assert(thread_context_for(&state->thread_contexts, INT2FIX(0), true, &context) == MITERUBY_SERIALIZER_OK);
  rb_raise(rb_eRuntimeError, "Interrupted preparation");
}

static void test_retained_preparation_state(void) {
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
    miteruby_allocator_free(&state->compressed_serialization_buffer);
    state->compressed_serialization_buffer = miteruby_allocator_alloc(1024, "test_output");
    assert(state->compressed_serialization_buffer != NULL);
    miteruby_allocator_free(&state->interned_events_queue);
    state->interned_events_queue = miteruby_allocator_alloc(1024, "test_queue");
    assert(state->interned_events_queue != NULL);
    assert(serializer_size(state) == sizeof(*state) + miteruby_allocator_requested_bytes());
    state->status = SERIALIZER_PREPARE;
    state->compressed_serialization_size = scenario == BUFFER_FULL ? 1023 : 0;
    state->stream = pb_ostream_from_buffer(input, 1024);
    verstable_serializer_thread_contexts_map_clear(&state->thread_contexts);
    if (scenario == RUBY_EXCEPTION) {
      int error = 0;
      rb_protect(prepare_with_exception, (VALUE)state, &error);
      assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
      rb_set_errinfo(Qnil);
    } else {
      fail_allocations = scenario == REUSE_AFTER_EXCEPTION;
      miteruby_serializer_exit_reason_t reason = initialize_compression(state);
      assert(reason == MITERUBY_SERIALIZER_OK);
      serializer_thread_context *context;
      assert(thread_context_for(&state->thread_contexts, INT2FIX(0), true, &context) == MITERUBY_SERIALIZER_OK);
      assert(pb_write(&state->stream, (const pb_byte_t *)"profile", 7));
      reason = compress_buffer(state, ZSTD_e_end);
      assert(reason == (scenario == BUFFER_FULL ? MITERUBY_SERIALIZER_COMPRESSED_BUFFER_FULL : MITERUBY_SERIALIZER_OK));
      if (reason == MITERUBY_SERIALIZER_OK) {
        assert(state->compressed_serialization_size > 0);
      }
      fail_allocations = false;
    }
    if (scenario == SUCCESS) {
      persistent_bytes = miteruby_allocator_requested_bytes();
    }
    assert(state->compression_workspace == workspace);
    assert(miteruby_allocator_requested_bytes() == persistent_bytes);
    assert(serializer_size(state) == sizeof(*state) + persistent_bytes);
    assert(state->status == SERIALIZER_PREPARE);
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
  const serializer_status unfinished_statuses[] = {SERIALIZER_PREPARE, SERIALIZER_NO_GVL};
  size_t idle_bytes = miteruby_allocator_requested_bytes();
  for (size_t i = 0; i < sizeof(unfinished_statuses) / sizeof(unfinished_statuses[0]); i++) {
    state->status = unfinished_statuses[i];
    uint8_t *queue = miteruby_allocator_alloc(1024, "test_queue");
    assert(queue != NULL);
    int error = 0;
    if (state->status == SERIALIZER_NO_GVL) {
      assert(miteruby_serializer_prepare_serialize(serializer, queue, 0, NULL, NULL, NULL) == MITERUBY_SERIALIZER_ALREADY_WORKING);
      assert(state->interned_events_queue == NULL);
      rb_protect(check_available, serializer, &error);
      assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
      assert(state->status == SERIALIZER_NO_GVL);
      rb_set_errinfo(Qnil);
    } else {
      miteruby_serializer_check_available(serializer);
    }
    rb_protect(serialize_working_profile, serializer, &error);
    assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
    assert(state->status == unfinished_statuses[i]);
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
  }

  miteruby_mark_frame_array_t frames = {0};
  miteruby_location_array_t locations = {0};
  verstable_mark_threads_set threads;
  verstable_mark_threads_set_init(&threads);
  uint8_t *queue = miteruby_allocator_alloc(1024, "test_queue");
  assert(queue != NULL);
  assert(miteruby_serializer_prepare_serialize(serializer, queue, 0, &frames, &locations, &threads) == MITERUBY_SERIALIZER_OK);
  assert(state->interned_events_queue == queue);
  assert(state->status == SERIALIZER_NO_GVL);
  assert(miteruby_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_OK);
  assert(state->interned_events_queue == NULL);
  assert(state->status == SERIALIZER_FINISHED);
  assert(miteruby_allocator_alloc_size(state->compressed_serialization_buffer) == MAX_COMPRESSED_BUFFER_BYTES);
  assert(miteruby_allocator_requested_bytes() == idle_bytes);
  assert(native_reset_after_fork(Qnil, serializer) == Qtrue);
  assert(state->compressed_serialization_buffer != NULL);
  assert(state->status == SERIALIZER_EMPTY);
  assert(miteruby_allocator_requested_bytes() == idle_bytes);
  verstable_mark_threads_set_cleanup(&threads);
  RB_GC_GUARD(serializer);
}

static void test_missing_thread_context(void) {
  VALUE serializer = serializer_new(rb_cObject);
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  size_t idle_bytes = miteruby_allocator_requested_bytes();
  miteruby_mark_frame_array_t frames = {0};
  miteruby_location_array_t locations = {0};
  verstable_mark_threads_set threads;
  verstable_mark_threads_set_init(&threads);
  miteruby_event_deduped_sample_t *event = miteruby_allocator_alloc(sizeof(*event), "test_queue");
  assert(event != NULL);
  *event = (miteruby_event_deduped_sample_t) {
    .header = {.size_bytes = sizeof(*event)},
    .thread = {.value = rb_thread_current()},
  };
  assert(miteruby_serializer_prepare_serialize(
    serializer, (uint8_t *)event, sizeof(*event), &frames, &locations, &threads
  ) == MITERUBY_SERIALIZER_OK);
  assert(miteruby_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_THREAD_CONTEXT_MISSING);
  assert(verstable_serializer_thread_contexts_map_size(&state->thread_contexts) == 0);
  assert(state->thread_contexts.buckets == NULL);
  assert(state->status == SERIALIZER_EMPTY);
  assert(state->interned_events_queue == NULL);
  assert(miteruby_allocator_requested_bytes() == idle_bytes);
  verstable_mark_threads_set_cleanup(&threads);
  RB_GC_GUARD(serializer);
}

static VALUE prepare_empty_profile_with_gvl(VALUE serializer) {
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

static VALUE prepare_empty_profile(VALUE serializer) {
  prepare_empty_profile_with_gvl(serializer);
  assert(miteruby_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_OK);
  return Qnil;
}

static VALUE profile_from_custom(VALUE klass, VALUE start, VALUE finish, VALUE bytes) {
  return bytes;
}

static VALUE finish_profile_thread(void *serializer) {
  miteruby_consumer_prepare_serialize((VALUE)serializer);
  return INT2FIX(MITERUBY_SERIALIZER_OK);
}

static VALUE thread_value(VALUE thread) {
  return rb_funcall(thread, rb_intern("value"), 0);
}

static miteruby_raw_events_queue_t *test_no_gvl_completion(void) {
  enum { SUCCESS, RAISE_DURING, KILL_DURING, RAISE_BEFORE, KILL_BEFORE };
  assert(mtx_init(&gate_mutex, mtx_plain) == thrd_success);
  assert(cnd_init(&gate_condition) == thrd_success);
  miteruby_raw_events_queue_t *raw_events_queue = miteruby_consumer_init();
  miteruby_consumer_reset();
  VALUE serializer = serializer_new(rb_cObject);
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  size_t idle_bytes = miteruby_allocator_requested_bytes();

  for (int scenario = SUCCESS; scenario <= KILL_BEFORE; scenario++) {
    no_gvl_mode = scenario >= RAISE_BEFORE ? GATE_BEFORE : GATE_DURING;
    gate_entered = gate_released = false;
    VALUE worker = rb_thread_create(finish_profile_thread, (void *)serializer);
    rb_funcall(worker, rb_intern("report_on_exception="), 1, Qfalse);
    rb_thread_call_without_gvl(wait_for_no_gvl, NULL, NULL, NULL);
    assert(state->status == SERIALIZER_NO_GVL);
    assert(state->interned_events_queue != NULL);
    miteruby_consumer_reset();
    VALUE stats = rb_hash_new();
    miteruby_consumer_stats(stats);
    assert(NUM2SIZET(rb_hash_aref(stats, ID2SYM(rb_intern("miteruby_interned_events_queue_used_size_bytes")))) == 0);
    int error = 0;
    rb_protect(check_available, serializer, &error);
    assert(error != 0);
    rb_set_errinfo(Qnil);
    rb_protect(serialize_working_profile, serializer, &error);
    assert(error != 0);
    rb_set_errinfo(Qnil);

    if (scenario == SUCCESS) {
      rb_gc_start();
      if (rb_respond_to(rb_mGC, rb_intern("verify_compaction_references")))
        rb_funcall(rb_mGC, rb_intern("verify_compaction_references"), 0);
      assert(serializer_size(state) > 0);
      VALUE child = rb_funcall(rb_mProcess, rb_intern("fork"), 0);
      if (NIL_P(child)) {
        no_gvl_mode = NO_GATE;
        native_reset_after_fork(Qnil, serializer);
        prepare_empty_profile(serializer);
        native_serialize(Qnil, serializer);
        _exit(0);
      }
      int child_status;
      assert(waitpid(NUM2INT(child), &child_status, 0) == NUM2INT(child));
      assert(WIFEXITED(child_status) && WEXITSTATUS(child_status) == 0);
    } else if (scenario == RAISE_DURING || scenario == RAISE_BEFORE) {
      rb_funcall(worker, rb_intern("raise"), 1, rb_str_new_cstr("Interrupted serialization"));
    } else {
      rb_funcall(worker, rb_intern("kill"), 0);
    }

    assert(mtx_lock(&gate_mutex) == thrd_success);
    gate_released = true;
    assert(cnd_broadcast(&gate_condition) == thrd_success);
    assert(mtx_unlock(&gate_mutex) == thrd_success);
    VALUE result = rb_protect(thread_value, worker, &error);
    no_gvl_mode = NO_GATE;
    if (scenario == RAISE_DURING || scenario == RAISE_BEFORE) {
      assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
      rb_set_errinfo(Qnil);
    } else {
      assert(error == 0);
      assert(result == (scenario == SUCCESS ? INT2FIX(MITERUBY_SERIALIZER_OK) : Qnil));
    }
    assert(state->status == (scenario < RAISE_BEFORE ? SERIALIZER_FINISHED : SERIALIZER_EMPTY));
    assert((state->interned_events_queue == NULL) == (scenario == SUCCESS));
    miteruby_serializer_check_available(serializer);
    // GC above can reclaim serializers from earlier tests, so compare allocation counts after it.
    if (scenario == SUCCESS) idle_bytes = miteruby_allocator_requested_bytes();
    assert(miteruby_allocator_requested_bytes() == idle_bytes + miteruby_allocator_alloc_size(state->interned_events_queue));
    if (scenario < RAISE_BEFORE) native_serialize(Qnil, serializer);
    prepare_empty_profile(serializer);
    assert(state->interned_events_queue == NULL);
    assert(miteruby_allocator_requested_bytes() == idle_bytes);
    native_serialize(Qnil, serializer);
    RB_GC_GUARD(worker);
  }
  cnd_destroy(&gate_condition);
  mtx_destroy(&gate_mutex);
  RB_GC_GUARD(serializer);
  return raw_events_queue;
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

  fail_preparation_encoding = true;
  rb_protect(prepare_empty_profile, serializer, &error);
  fail_preparation_encoding = false;
  assert(error != 0);
  rb_set_errinfo(Qnil);
  assert(state->status == SERIALIZER_PREPARE);
  assert(state->interned_events_queue != NULL);
  assert(miteruby_allocator_requested_bytes() == idle_bytes + 1024);
  miteruby_serializer_check_available(serializer);
  rb_protect(serialize_working_profile, serializer, &error);
  assert(error != 0);
  rb_set_errinfo(Qnil);
  assert(state->status == SERIALIZER_PREPARE);
  prepare_empty_profile(serializer);
  assert(state->status == SERIALIZER_FINISHED);
  assert(state->interned_events_queue == NULL);
  assert(miteruby_allocator_requested_bytes() == idle_bytes);
  native_serialize(Qnil, serializer);
  RB_GC_GUARD(serializer);
}

int main(int argc, char **argv) {
  ruby_sysinit(&argc, &argv);
  RUBY_INIT_STACK;
  ruby_init();
  char program[] = "miteruby-serializer", disable[] = "--disable=gems,rubyopt", eval[] = "-e", script[] = "";
  char *ruby_args[] = {program, disable, eval, script};
  assert(ruby_exec_node(ruby_options(4, ruby_args)) == 0);
  VALUE datadog = rb_define_module("Datadog");
  VALUE profiling = rb_define_module_under(datadog, "Profiling");
  VALUE encoded_profile = rb_define_class_under(profiling, "EncodedProfile", rb_cObject);
  rb_define_singleton_method(encoded_profile, "from_custom", profile_from_custom, 3);
  test_sample_values();
  test_reuse_after_error();
  test_retained_preparation_state();
  test_working_status();
  test_missing_thread_context();
  test_compressed_buffer_lifecycle();
  miteruby_raw_events_queue_t *raw_events_queue = test_no_gvl_completion();
  puts("Miteruby serializer tests passed");
  int result = ruby_cleanup(0);
  miteruby_raw_events_queue_destroy(raw_events_queue);
  miteruby_allocator_free(&raw_events_queue);
  return result;
}
