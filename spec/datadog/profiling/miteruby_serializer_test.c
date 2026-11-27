#define _GNU_SOURCE 1
#include <ruby.h>
#include "../../../ext/datadog_profiling_native_extension/encoded_profile.h"
#include "miteruby_test_support.h"
#include "../../../ext/datadog_profiling_native_extension/miteruby/raw_events_queue_marking.c"
#include "../../../ext/datadog_profiling_native_extension/miteruby/pprof/pb_encode.h"
#include "../../../ext/datadog_profiling_native_extension/ruby_helpers.h"
#include "../../../ext/datadog_profiling_native_extension/miteruby/sample_event.h"
#include <stdbool.h>
#include <string.h>
#include <ruby/thread.h>
#include <pthread.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../../../ext/datadog_profiling_native_extension/miteruby/stack_dedup.c"
#include "../../../ext/datadog_profiling_native_extension/miteruby/pprof/zstd.c"

#undef NDEBUG
#include <assert.h>

void setup_signal_handler_init(VALUE profiling_module);
void encoded_profile_init(VALUE profiling_module);
RUBY_EXTERN const rb_iseq_t *rb_proc_get_iseq(VALUE proc, int *is_proc);
RUBY_EXTERN unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);

static bool fail_allocations;
static const char *failed_allocation_name;
static void (*during_preparation)(void);
static bool fail_profile_wrapping;
static bool fail_preparation_encoding;
static bool fail_preparation_return;
static enum { NO_GATE, GATE_BEFORE, GATE_DURING } no_gvl_mode;
static pthread_mutex_t gate_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gate_condition = PTHREAD_COND_INITIALIZER;
static bool gate_entered, gate_released;

static void *pause_no_gvl(void *unused) {
  assert(!ruby_thread_has_gvl_p());
  assert(pthread_mutex_lock(&gate_mutex) == 0);
  gate_entered = true;
  assert(pthread_cond_broadcast(&gate_condition) == 0);
  while (!gate_released) assert(pthread_cond_wait(&gate_condition, &gate_mutex) == 0);
  assert(pthread_mutex_unlock(&gate_mutex) == 0);
  return NULL;
}

static void *wait_for_no_gvl(void *unused) {
  assert(pthread_mutex_lock(&gate_mutex) == 0);
  while (!gate_entered) assert(pthread_cond_wait(&gate_condition, &gate_mutex) == 0);
  assert(pthread_mutex_unlock(&gate_mutex) == 0);
  return NULL;
}

static void *test_call_without_gvl(void *(*callback)(void *), void *args, rb_unblock_function_t *ubf, void *ubf_args) {
  // Leave the interruption pending so the real call handles it before starting serialization.
  if (no_gvl_mode == GATE_BEFORE) rb_thread_call_without_gvl2(pause_no_gvl, NULL, ubf, ubf_args);
  return rb_thread_call_without_gvl(callback, args, ubf, ubf_args);
}

static void *test_allocator_alloc(size_t size, const char *name) {
  if (fail_allocations || (failed_allocation_name != NULL && strcmp(name, failed_allocation_name) == 0)) return NULL;
  return miteruby_allocator_alloc(size, name);
}

static VALUE test_wrap_encoded_profile(ddog_prof_EncodedProfile profile) {
  if (fail_profile_wrapping) {
    ddog_prof_EncodedProfile_drop(&profile);
    rb_raise(rb_eRuntimeError, "Profile wrapping failed");
  }
  return from_ddog_prof_EncodedProfile(profile);
}

static bool test_pb_encode_tag(pb_ostream_t *stream, pb_wire_type_t type, uint32_t tag) {
  if (during_preparation != NULL) {
    void (*callback)(void) = during_preparation;
    during_preparation = NULL;
    callback();
  }
  if (fail_preparation_encoding) rb_raise(rb_eRuntimeError, "Interrupted preparation");
  if (fail_preparation_return) return false;
  return pb_encode_tag(stream, type, tag);
}

static bool test_pb_encode(pb_ostream_t *stream, const pb_msgdesc_t *fields, const void *src_struct) {
  if (no_gvl_mode == GATE_DURING && !ruby_thread_has_gvl_p()) pause_no_gvl(NULL);
  return pb_encode(stream, fields, src_struct);
}

#define from_ddog_prof_EncodedProfile test_wrap_encoded_profile
#define miteruby_allocator_alloc test_allocator_alloc
#define pb_encode test_pb_encode
#define pb_encode_tag test_pb_encode_tag
#define rb_thread_call_without_gvl test_call_without_gvl
#include "../../../ext/datadog_profiling_native_extension/miteruby/serializer.c"
#undef rb_thread_call_without_gvl
#undef pb_encode_tag
#undef pb_encode
#undef miteruby_allocator_alloc
#undef from_ddog_prof_EncodedProfile

#define miteruby_allocator_alloc test_allocator_alloc
#include "../../../ext/datadog_profiling_native_extension/miteruby/consumer.c"
#undef miteruby_allocator_alloc

static size_t mapped_allocation_size(const void *allocation) {
  if (allocation == NULL) return 0;
  size_t size = miteruby_allocator_alloc_size(allocation) + 16;
  size_t page_size = (size_t)sysconf(_SC_PAGESIZE);
  return ((size + page_size - 1) / page_size) * page_size;
}

static miteruby_serializer_exit_reason_t prepare_batch(
  VALUE serializer, uint8_t *queue, size_t size,
  miteruby_mark_function_array_t *functions, miteruby_location_array_t *locations, verstable_mark_threads_set *threads
) {
  miteruby_serializer_exit_reason_t reason = serializer_step1_serialize_with_gvl_with_consumer_lock(serializer, queue, size, functions, locations, threads);
  return reason == MITERUBY_SERIALIZER_OK ? serializer_step2_serialize_with_gvl_no_consumer_lock(serializer) : reason;
}

static void test_location_wire_encoding(void) {
  const uint64_t ids[] = {0, 1, 127, 128, 16383, 16384, UINT64_MAX};
  const int64_t lines[] = {0, 1, 127, 128, INT64_MAX, -1, INT64_MIN};
  for (size_t i = 0; i < sizeof(ids) / sizeof(ids[0]); i++) {
    for (size_t j = 0; j < sizeof(ids) / sizeof(ids[0]); j++) {
      for (size_t k = 0; k < sizeof(lines) / sizeof(lines[0]); k++) {
        uint8_t expected[MITERUBY_PPROF_FRAGMENT_LOCATION_SIZE], actual[sizeof(expected)];
        pb_ostream_t reference = pb_ostream_from_buffer(expected, sizeof(expected));
        miteruby_pprof_fragment_location_t fragment = {.has_location = true, .location = {
          .id = ids[i], .has_line = true, .line = {.function_id = ids[j], .line = lines[k]},
        }};
        assert(pb_encode(&reference, MITERUBY_PPROF_FRAGMENT_LOCATION_FIELDS, &fragment));
        pb_ostream_t output = pb_ostream_from_buffer(actual, reference.bytes_written);
        assert(emit_location_fragment(&output, ids[i], ids[j], lines[k]) == MITERUBY_SERIALIZER_OK);
        assert(output.bytes_written == reference.bytes_written && memcmp(actual, expected, output.bytes_written) == 0);
        output = pb_ostream_from_buffer(actual, reference.bytes_written - 1);
        assert(emit_location_fragment(&output, ids[i], ids[j], lines[k]) == MITERUBY_SERIALIZER_LOCATION_ENCODING_ERROR);
      }
    }
  }
}

static void test_safe_line_lookup(void) {
  VALUE fixture = rb_eval_string(
    "sample = proc {\n 42\n}; "
    "[sample, RubyVM::InstructionSequence.of(sample).to_a.last.grep(Array).sum(&:length)]"
  );
  VALUE proc = rb_ary_entry(fixture, 0);
  size_t bytecode_size = NUM2SIZET(rb_ary_entry(fixture, 1));
  const rb_iseq_t *iseq = rb_proc_get_iseq(proc, NULL);
  assert(iseq != NULL);
  assert(bytecode_size > 0);
  for (size_t pos = 0; pos < bytecode_size; pos++) {
    assert(safe_rb_iseq_line_no(iseq, pos) == rb_iseq_line_no(iseq, pos));
  }
  assert(safe_rb_iseq_line_no(iseq, bytecode_size) == 0);
  assert(safe_rb_iseq_line_no(iseq, UINT16_MAX - 1) == 0);
  assert(safe_rb_iseq_line_no(iseq, SIZE_MAX) == 0);
  assert(safe_rb_iseq_line_no(NULL, 0) == 0);
  RB_GC_GUARD(fixture);
}

static void test_sample_values(void) {
  verstable_serializer_thread_contexts_map contexts;
  const struct {
    int thread;
    long cpu, monotonic, expected_cpu, expected_wall;
  } samples[] = {
    {1, -1, 100, 1000000, 1000000},
    {2, 50, 110, 1000000, 1000000},
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
    if (serialization == 0) allocated_bytes = miteruby_allocator_currently_allocated_bytes_stat();
    else assert(miteruby_allocator_currently_allocated_bytes_stat() == allocated_bytes);
  }
  verstable_serializer_thread_contexts_map_cleanup(&contexts);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
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
  size_t allocated_bytes = miteruby_allocator_currently_allocated_bytes_stat();
  verstable_serializer_thread_contexts_map_clear(&contexts);
  miteruby_event_deduped_sample_t event = {.header = {.cpu_time = {.ns = 100}, .timestamp = {.ns = 200}}};
  assert(thread_context_for(&contexts, INT2FIX(0), true, &context) == MITERUBY_SERIALIZER_OK);
  miteruby_sample_values values = sample_values_for(context, &event);
  assert(values.cpu_time_ns == 1000000 && values.wall_time_ns == 1000000);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == allocated_bytes);
  fail_allocations = false;
  verstable_serializer_thread_contexts_map_cleanup(&contexts);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
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
  size_t persistent_bytes = miteruby_allocator_currently_allocated_bytes_stat();
  size_t persistent_size = 0;
  miteruby_serializer_persistent_state_t *state = ruby_xcalloc(1, sizeof(*state));
  state->uncompressed_serialization_buffer = input;
  verstable_serializer_thread_contexts_map_init(&state->thread_contexts);
  verstable_mark_threads_set_init(&state->threads_set);
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
    assert(serializer_size(state) == sizeof(*state) + 3 * 1024 + ZSTD_estimateCStreamSize(COMPRESSION_LEVEL) +
      miteruby_allocator_alloc_size(state->thread_contexts.buckets));
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
      persistent_bytes = miteruby_allocator_currently_allocated_bytes_stat();
      persistent_size = serializer_size(state);
    }
    assert(state->compression_workspace == workspace);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == persistent_bytes);
    assert(serializer_size(state) == persistent_size);
    assert(state->status == SERIALIZER_PREPARE);
    assert(state->interned_events_queue != NULL);
    assert(miteruby_allocator_alloc_size(input) == 1024);
    assert(miteruby_allocator_alloc_size(state->compressed_serialization_buffer) == 1024);
  }
  assert(state->interned_events_queue != NULL);
  serializer_free(state);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
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
  size_t idle_bytes = miteruby_allocator_currently_allocated_bytes_stat();
  for (size_t i = 0; i < sizeof(unfinished_statuses) / sizeof(unfinished_statuses[0]); i++) {
    state->status = unfinished_statuses[i];
    uint8_t *queue = miteruby_allocator_alloc(1024, "test_queue");
    assert(queue != NULL);
    int error = 0;
    assert(prepare_batch(serializer, queue, 0, NULL, NULL, NULL) == MITERUBY_SERIALIZER_ALREADY_WORKING);
    assert(state->interned_events_queue == NULL);
    rb_protect(check_available, serializer, &error);
    assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
    assert(state->status == unfinished_statuses[i]);
    rb_set_errinfo(Qnil);
    rb_protect(serialize_working_profile, serializer, &error);
    assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
    assert(state->status == unfinished_statuses[i]);
    rb_set_errinfo(Qnil);

    state->compressed_serialization_size = 123;
    state->start_time_ns = 0;
    state->finish_time_ns = 0;
    state->interned_events_queue = queue;
    assert(state->compressed_serialization_buffer != NULL);
    size_t allocated_bytes = miteruby_allocator_currently_allocated_bytes_stat();
    size_t queue_bytes = mapped_allocation_size(queue);
    assert(native_reset_after_fork(Qnil, serializer) == Qtrue);
    assert(state->interned_events_queue == NULL);
    assert(state->compressed_serialization_buffer != NULL);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == allocated_bytes - queue_bytes);
    assert(state->status == SERIALIZER_EMPTY);
    miteruby_serializer_check_available(serializer);
    assert(state->compressed_serialization_size == 0);
    assert(state->start_time_ns > 0);
    assert(state->finish_time_ns == state->start_time_ns);
  }

  miteruby_mark_function_array_t functions = {0};
  miteruby_location_array_t locations = {0};
  verstable_mark_threads_set threads;
  verstable_mark_threads_set_init(&threads);
  uint8_t *queue = miteruby_allocator_alloc(1024, "test_queue");
  assert(queue != NULL);
  assert(prepare_batch(serializer, queue, 0, &functions, &locations, &threads) == MITERUBY_SERIALIZER_OK);
  assert(state->interned_events_queue == queue);
  assert(state->status == SERIALIZER_NO_GVL);
  assert(serializer_step3_serialize_no_gvl_no_consumer_lock(serializer) == MITERUBY_SERIALIZER_OK);
  assert(state->interned_events_queue == NULL);
  assert(state->status == SERIALIZER_FINISHED);
  assert(miteruby_allocator_alloc_size(state->compressed_serialization_buffer) == MAX_COMPRESSED_BUFFER_BYTES);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
  assert(native_reset_after_fork(Qnil, serializer) == Qtrue);
  assert(state->compressed_serialization_buffer != NULL);
  assert(state->status == SERIALIZER_EMPTY);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
  verstable_mark_threads_set_cleanup(&threads);
  RB_GC_GUARD(serializer);
}

static void test_missing_thread_context(void) {
  VALUE serializer = serializer_new(rb_cObject);
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  size_t idle_bytes = miteruby_allocator_currently_allocated_bytes_stat();
  miteruby_mark_function_array_t functions = {0};
  miteruby_location_array_t locations = {0};
  verstable_mark_threads_set threads;
  verstable_mark_threads_set_init(&threads);
  miteruby_event_deduped_sample_t *event = miteruby_allocator_alloc(sizeof(*event), "test_queue");
  assert(event != NULL);
  *event = (miteruby_event_deduped_sample_t) {
    .header = {.size_bytes = sizeof(*event)},
    .thread = {.value = rb_thread_current()},
  };
  assert(prepare_batch(
    serializer, (uint8_t *)event, sizeof(*event), &functions, &locations, &threads
  ) == MITERUBY_SERIALIZER_OK);
  assert(serializer_step3_serialize_no_gvl_no_consumer_lock(serializer) == MITERUBY_SERIALIZER_THREAD_CONTEXT_MISSING);
  assert(verstable_serializer_thread_contexts_map_size(&state->thread_contexts) == 0);
  assert(state->thread_contexts.buckets == NULL);
  assert(state->status == SERIALIZER_EMPTY);
  assert(state->interned_events_queue == NULL);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
  verstable_mark_threads_set_cleanup(&threads);
  RB_GC_GUARD(serializer);
}

static VALUE prepare_empty_profile_with_gvl(VALUE serializer) {
  miteruby_mark_function_array_t functions = {0};
  miteruby_location_array_t locations = {0};
  verstable_mark_threads_set threads;
  verstable_mark_threads_set_init(&threads);
  uint8_t *queue = miteruby_allocator_alloc(1024, "test_queue");
  assert(queue != NULL);
  assert(prepare_batch(serializer, queue, 0, &functions, &locations, &threads) == MITERUBY_SERIALIZER_OK);
  verstable_mark_threads_set_cleanup(&threads);
  return Qnil;
}

static VALUE prepare_empty_profile(VALUE serializer) {
  prepare_empty_profile_with_gvl(serializer);
  assert(serializer_step3_serialize_no_gvl_no_consumer_lock(serializer) == MITERUBY_SERIALIZER_OK);
  return Qnil;
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
  miteruby_raw_events_queue_t *raw_events_queue = consumer_state.raw_events_queue;
  miteruby_consumer_reset();
  VALUE serializer = serializer_new(rb_cObject);
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  size_t idle_bytes = miteruby_allocator_currently_allocated_bytes_stat();

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

    assert(pthread_mutex_lock(&gate_mutex) == 0);
    gate_released = true;
    assert(pthread_cond_broadcast(&gate_condition) == 0);
    assert(pthread_mutex_unlock(&gate_mutex) == 0);
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
    if (scenario == SUCCESS) idle_bytes = miteruby_allocator_currently_allocated_bytes_stat();
    assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes + mapped_allocation_size(state->interned_events_queue));
    if (scenario < RAISE_BEFORE) native_serialize(Qnil, serializer);
    prepare_empty_profile(serializer);
    assert(state->interned_events_queue == NULL);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
    native_serialize(Qnil, serializer);
    RB_GC_GUARD(worker);
  }
  assert(pthread_cond_destroy(&gate_condition) == 0);
  assert(pthread_mutex_destroy(&gate_mutex) == 0);
  RB_GC_GUARD(serializer);
  return raw_events_queue;
}

static void test_compressed_buffer_lifecycle(void) {
  VALUE serializer = serializer_new(rb_cObject);
  miteruby_serializer_persistent_state_t *state = get_state(serializer);
  size_t idle_bytes = miteruby_allocator_currently_allocated_bytes_stat();
  assert(state->compressed_serialization_buffer != NULL);

  for (int cycle = 0; cycle < 2; cycle++) {
    prepare_empty_profile(serializer);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
    prepare_empty_profile(serializer);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
    uint8_t *previous_buffer = state->compressed_serialization_buffer;
    VALUE expected_bytes = rb_str_new((const char *) previous_buffer, state->compressed_serialization_size);
    VALUE result = native_serialize(Qnil, serializer);
    assert(state->compressed_serialization_buffer != previous_buffer);
    assert(state->compressed_serialization_buffer[0] == 0);
    VALUE actual_bytes = rb_funcall(rb_ary_entry(result, 2), rb_intern("_native_bytes"), 0);
    assert(rb_str_equal(actual_bytes, expected_bytes) == Qtrue);
    assert(state->status == SERIALIZER_EMPTY);
    assert(state->compressed_serialization_buffer != NULL);
    assert(state->compressed_serialization_size == 0);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
  }

  prepare_empty_profile(serializer);
  uint8_t *previous_buffer = state->compressed_serialization_buffer;
  size_t previous_size = state->compressed_serialization_size;
  int64_t lost_finish = state->finish_time_ns;
  fail_profile_wrapping = true;
  int error = 0;
  rb_protect(serialize_working_profile, serializer, &error);
  fail_profile_wrapping = false;
  assert(error != 0);
  rb_set_errinfo(Qnil);
  assert(state->status == SERIALIZER_EMPTY);
  assert(state->compressed_serialization_buffer == previous_buffer);
  assert(state->compressed_serialization_size == previous_size);
  assert(state->start_time_ns == lost_finish);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);

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
  assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
  prepare_empty_profile(serializer);
  native_serialize(Qnil, serializer);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);

  fail_preparation_encoding = true;
  rb_protect(prepare_empty_profile, serializer, &error);
  fail_preparation_encoding = false;
  assert(error != 0);
  rb_set_errinfo(Qnil);
  assert(state->status == SERIALIZER_EMPTY);
  assert(state->interned_events_queue == NULL);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
  miteruby_serializer_check_available(serializer);
  rb_protect(serialize_working_profile, serializer, &error);
  assert(error != 0);
  rb_set_errinfo(Qnil);
  assert(state->status == SERIALIZER_EMPTY);
  prepare_empty_profile(serializer);
  assert(state->status == SERIALIZER_FINISHED);
  assert(state->interned_events_queue == NULL);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == idle_bytes);
  native_serialize(Qnil, serializer);
  RB_GC_GUARD(serializer);
}

static VALUE snapshot_serializer;
static enum { HANDOFF_OK, HANDOFF_EXCEPTION, HANDOFF_ENCODING_ERROR } handoff_outcome;

static VALUE publish_snapshot_sample(DDTRACE_UNUSED VALUE self) {
  assert(miteruby_sample_event_publish_mask(consumer_state.raw_events_queue, sigprof_signal_mask));
  return Qnil;
}

static void *consume_snapshot_sample(DDTRACE_UNUSED void *unused) {
  assert(pthread_mutex_trylock(&consumer_state.mutex) == 0);
  miteruby_raw_events_queue_record_t record = miteruby_raw_events_queue_read(consumer_state.raw_events_queue, NULL);
  assert(record.data != NULL);
  assert(buffer_event((const miteruby_event_header_t *)record.data) == MITERUBY_CONSUMER_OK);
  assert(miteruby_raw_events_queue_read(consumer_state.raw_events_queue, NULL).data == NULL);
  assert(pthread_mutex_unlock(&consumer_state.mutex) == 0);
  return NULL;
}

static void check_detached_batch(void) {
  miteruby_serializer_persistent_state_t *state = get_state(snapshot_serializer);
  assert(state->status == SERIALIZER_PREPARE);
  assert(state->interned_events_pos > 0 && state->mark_function_array.count > 0 && state->location_array.count > 0);
  assert(verstable_mark_threads_set_size(&state->threads_set) == 1);
  assert(state->mark_function_array.entries != consumer_state.mark_function_array.entries);
  assert(state->location_array.entries != consumer_state.location_array.entries);
  assert(state->interned_events_queue != consumer_state.interned_events_queue);
  assert(consumer_state.interned_events_pos == 0 && consumer_state.mark_function_array.count == 0);
  assert(consumer_state.mark_function_set.ctx == &consumer_state.mark_function_array);
  assert(consumer_state.location_set.ctx == &consumer_state.location_array);

  rb_eval_string("Class.new { def next_batch; Datadog::Profiling.capture_snapshot_sample; end }.new.next_batch");
  pthread_t consumer;
  assert(pthread_create(&consumer, NULL, consume_snapshot_sample, NULL) == 0);
  void *result;
  assert(pthread_join(consumer, &result) == 0 && result == NULL);
  assert(consumer_state.interned_events_pos > 0 && consumer_state.mark_function_array.count > 0);

  int error = 0;
  rb_protect(check_available, snapshot_serializer, &error);
  assert(error != 0);
  rb_set_errinfo(Qnil);
  rb_gc_start();
  if (rb_respond_to(rb_mGC, rb_intern("verify_compaction_references")))
    rb_funcall(rb_mGC, rb_intern("verify_compaction_references"), 0);
  if (handoff_outcome == HANDOFF_EXCEPTION) rb_raise(rb_eRuntimeError, "Preparation failed after consumption");
  if (handoff_outcome == HANDOFF_ENCODING_ERROR) {
    fail_preparation_return = true;
    return;
  }

  size_t detached_bytes = mapped_allocation_size(state->interned_events_queue) +
    mapped_allocation_size(state->mark_function_array.entries) + mapped_allocation_size(state->location_array.entries) +
    mapped_allocation_size(state->threads_set.buckets);
  size_t bytes = miteruby_allocator_currently_allocated_bytes_stat();
  VALUE child = rb_funcall(rb_mProcess, rb_intern("fork"), 0);
  if (NIL_P(child)) {
    native_reset_after_fork(Qnil, snapshot_serializer);
    assert(state->status == SERIALIZER_EMPTY && state->mark_function_array.entries == NULL);
    assert(state->location_array.entries == NULL && state->threads_set.buckets == NULL);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == bytes - detached_bytes);
    _exit(0);
  }
  int child_status;
  assert(waitpid(NUM2INT(child), &child_status, 0) == NUM2INT(child));
  assert(WIFEXITED(child_status) && WEXITSTATUS(child_status) == 0);
  assert(state->status == SERIALIZER_PREPARE && state->mark_function_array.count > 0);
}

static VALUE prepare_consumer_batch(VALUE serializer) {
  miteruby_consumer_prepare_serialize(serializer);
  return Qnil;
}

static void test_batch_handoff(VALUE profiling) {
  miteruby_consumer_init();
  miteruby_consumer_reset();
  rb_define_singleton_method(profiling, "capture_snapshot_sample", publish_snapshot_sample, 0);
  snapshot_serializer = serializer_new(rb_cObject);
  rb_gc_register_address(&snapshot_serializer);
  miteruby_serializer_persistent_state_t *state = get_state(snapshot_serializer);

  const char *allocations[] = {"interned_events_queue", "mark_function_array", "location_array"};
  for (size_t i = 0; i < sizeof(allocations) / sizeof(allocations[0]); i++) {
    rb_eval_string("Datadog::Profiling.capture_snapshot_sample");
    consume_snapshot_sample(NULL);
    size_t bytes = miteruby_allocator_currently_allocated_bytes_stat();
    failed_allocation_name = allocations[i];
    int error = 0;
    rb_protect(prepare_consumer_batch, snapshot_serializer, &error);
    failed_allocation_name = NULL;
    assert(error != 0);
    rb_set_errinfo(Qnil);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == bytes);
    assert(consumer_state.interned_events_pos == 0 && consumer_state.mark_function_array.count == 0);
    assert(consumer_state.location_array.count == 0 && verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 0);
    assert(state->status == SERIALIZER_EMPTY && state->interned_events_queue == NULL);
    rb_eval_string("Datadog::Profiling.capture_snapshot_sample");
    pthread_t consumer;
    assert(pthread_create(&consumer, NULL, consume_snapshot_sample, NULL) == 0);
    void *result;
    assert(pthread_join(consumer, &result) == 0 && result == NULL);
    miteruby_consumer_reset();
  }

  for (int failure = HANDOFF_OK; failure <= HANDOFF_ENCODING_ERROR; failure++) {
    rb_eval_string("Thread.new { Class.new { def previous_batch; Datadog::Profiling.capture_snapshot_sample; end }.new.previous_batch }.join; nil");
    consume_snapshot_sample(NULL);
    handoff_outcome = failure;
    during_preparation = check_detached_batch;
    int error = 0;
    rb_protect(prepare_consumer_batch, snapshot_serializer, &error);
    fail_preparation_return = false;
    assert((error != 0) == (failure != HANDOFF_OK));
    if (error != 0) rb_set_errinfo(Qnil);
    assert(during_preparation == NULL);
    assert(state->status == (failure ? SERIALIZER_EMPTY : SERIALIZER_FINISHED));
    assert(state->mark_function_array.entries == NULL && state->mark_function_array.count == 0);
    assert(state->location_array.entries == NULL && state->location_array.count == 0);
    assert(state->threads_set.buckets == NULL && state->interned_events_queue == NULL);
    assert(consumer_state.interned_events_pos > 0 && consumer_state.mark_function_array.count > 0);
    if (!failure) native_serialize(Qnil, snapshot_serializer);
    assert(check_available(snapshot_serializer) == Qnil);
    miteruby_consumer_prepare_serialize(snapshot_serializer);
    assert(state->status == SERIALIZER_FINISHED);
    native_serialize(Qnil, snapshot_serializer);
    assert(consumer_state.interned_events_pos == 0);
  }
  rb_gc_unregister_address(&snapshot_serializer);
  snapshot_serializer = Qnil;
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
  encoded_profile_init(profiling);
  private_vm_api_access_init();
  setup_signal_handler_init(profiling);
  test_location_wire_encoding();
  test_safe_line_lookup();
  test_sample_values();
  test_reuse_after_error();
  test_retained_preparation_state();
  test_working_status();
  test_missing_thread_context();
  test_compressed_buffer_lifecycle();
  test_batch_handoff(profiling);
  miteruby_raw_events_queue_t *raw_events_queue = test_no_gvl_completion();
  puts("Miteruby serializer tests passed");
  int result = ruby_cleanup(0);
  miteruby_raw_events_queue_destroy(raw_events_queue);
  miteruby_allocator_free(raw_events_queue);
  return result;
}
