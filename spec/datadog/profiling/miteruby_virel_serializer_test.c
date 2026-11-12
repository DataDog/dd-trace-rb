#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"
#include <ruby.h>
#include <ruby/encoding.h>
#include <ruby/thread.h>
#include <threads.h>
#include <sys/wait.h>
#include <stdio.h>
#include <stdbool.h>

#undef NDEBUG
#include <assert.h>

static bool fail_allocation;
static bool pause_encoding;
static bool entered, released;
static mtx_t gate_mutex;
static cnd_t gate_condition;
static unsigned encoding_calls;

static VALUE test_str_encode(VALUE string, VALUE encoding, int flags, VALUE options) {
  encoding_calls++;
  return rb_str_encode(string, encoding, flags, options);
}

static void *test_alloc(size_t size, const char *name) {
  return fail_allocation ? NULL : miteruby_allocator_alloc(size, name);
}

static void *pause_without_gvl(void *unused) {
  (void) unused;
  assert(mtx_lock(&gate_mutex) == thrd_success);
  entered = true;
  assert(cnd_broadcast(&gate_condition) == thrd_success);
  while (!released) assert(cnd_wait(&gate_condition, &gate_mutex) == thrd_success);
  assert(mtx_unlock(&gate_mutex) == thrd_success);
  return NULL;
}

static void *test_without_gvl(void *(*callback)(void *), void *args, rb_unblock_function_t *ubf, void *ubf_args) {
  if (pause_encoding) rb_thread_call_without_gvl(pause_without_gvl, NULL, NULL, NULL);
  return rb_thread_call_without_gvl(callback, args, ubf, ubf_args);
}

#define miteruby_allocator_alloc test_alloc
#define rb_thread_call_without_gvl test_without_gvl
#define rb_str_encode test_str_encode
#include "../../../ext/datadog_profiling_native_extension/miteruby/virel_serializer.c"
#undef rb_str_encode
#undef rb_thread_call_without_gvl
#undef miteruby_allocator_alloc

static VALUE serializer_class;

static miteruby_serializer_exit_reason_t prepare(VALUE serializer, size_t count, const long *timestamps, const long *cpu) {
  size_t bytes = count * sizeof(miteruby_event_deduped_sample_t);
  uint8_t *events = bytes ? miteruby_allocator_alloc(bytes, "virel_test_events") : NULL;
  assert(bytes == 0 || events != NULL);
  for (size_t i = 0; i < count; i++) {
    miteruby_event_deduped_sample_t *event = (miteruby_event_deduped_sample_t *) (events + i * sizeof(miteruby_event_deduped_sample_t));
    *event = (miteruby_event_deduped_sample_t) {
      .header = {.size_bytes = sizeof(miteruby_event_deduped_sample_t), .timestamp = {.ns = timestamps[i]}, .cpu_time = {.ns = cpu[i]}},
      .thread = {.value = rb_thread_current()},
      .stack_id = {.offset = 0},
    };
    event->header.stack_truncated = i == 2;
  }
  verstable_mark_threads_set threads;
  verstable_mark_threads_set_init(&threads);
  if (count) assert(!verstable_mark_threads_set_is_end(verstable_mark_threads_set_get_or_insert(&threads, rb_thread_current())));
  miteruby_mark_frame_array_t frames = {0};
  miteruby_location_array_t locations = {0};
  miteruby_serializer_exit_reason_t reason = miteruby_virel_serializer_prepare_serialize(serializer, events, bytes, &frames, &locations, &threads);
  verstable_mark_threads_set_cleanup(&threads);
  if (count && reason == MITERUBY_SERIALIZER_OK) {
    virel_state *state = get_state(serializer);
    size_t offset = begin_pool(state, VIREL_FUNCTION, 1);
    write_varint(state, 1);
    write_string(state, rb_utf8_str_new_cstr("Example.\xce\xb1"));
    write_string(state, rb_str_new_cstr("example.rb"));
    end_event(state, offset);
    offset = begin_pool(state, VIREL_LOCATION, 2);
    for (size_t i = 0; i < 2; i++) {
      write_varint(state, i + 1);
      write_varint(state, 1);
      write_varint(state, 10 + i);
    }
    end_event(state, offset);
    state->location_count = 2;
    miteruby_event_deduped_sample_t *first = (miteruby_event_deduped_sample_t *) events;
    first->stack.frame_count = 2;
    uint8_t *cursor = first->stack.ids;
    const uint8_t *end = events + sizeof(miteruby_event_deduped_sample_t);
    assert(miteruby_compressed_deltas_write((uint20_t) {0}, (uint20_t) {0}, &cursor, end));
    assert(miteruby_compressed_deltas_write((uint20_t) {0}, (uint20_t) {.value = 1}, &cursor, end));
    first->stack.ids_size = cursor - first->stack.ids;
    for (size_t i = 0; i < count; i++) {
      ((miteruby_event_deduped_sample_t *) (events + i * sizeof(miteruby_event_deduped_sample_t)))->header.frame_count = 2;
    }
  }
  return reason;
}

static void finish(VALUE serializer) {
  assert(miteruby_virel_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_OK);
  assert(get_state(serializer)->events == NULL);
}

static void write_fixture(VALUE serializer, FILE *file) {
  VALUE result = native_serialize(Qnil, serializer);
  VALUE bytes = rb_ary_entry(result, 2);
  assert(fwrite(RSTRING_PTR(bytes), 1, RSTRING_LEN(bytes), file) == (size_t) RSTRING_LEN(bytes));
  RB_GC_GUARD(bytes);
}

static void test_varints(void) {
  virel_state state = {.output = miteruby_allocator_alloc(64, "virel_test_output")};
  write_varint(&state, 0);
  write_varint(&state, 127);
  write_varint(&state, 128);
  write_varint(&state, UINT64_MAX);
  const uint8_t expected[] = {0, 127, 128, 1, 255, 255, 255, 255, 255, 255, 255, 255, 255};
  assert(state.output_size == sizeof(expected));
  assert(memcmp(state.output, expected, sizeof(expected)) == 0);
  uint8_t too_large[64] = {0};
  write_bytes(&state, too_large, sizeof(too_large));
  assert(state.error == MITERUBY_SERIALIZER_VIREL_BUFFER_FULL);
  assert(state.output_size == sizeof(expected));
  miteruby_allocator_free(&state.output);
}

static void test_string_boundary(void) {
  virel_state state = {.output = miteruby_allocator_alloc(2048, "virel_test_string")};
  char text[1002];
  memset(text, 'a', 999);
  memcpy(text + 999, "\xe2\x82\xac", 3);
  write_string(&state, rb_utf8_str_new(text, sizeof(text)));
  assert(state.error == MITERUBY_SERIALIZER_OK);
  assert(state.output_size == 1002);
  assert(state.output[0] == 3 && state.output[1] == 231 && state.output[2] == 7);
  assert(memcmp(state.output + 3, text, 999) == 0);
  state.output_size = 0;
  write_string(&state, rb_str_new("\xff", 1));
  const uint8_t replacement[] = {3, 3, 0xef, 0xbf, 0xbd};
  assert(state.output_size == sizeof(replacement));
  assert(memcmp(state.output, replacement, sizeof(replacement)) == 0);
  miteruby_allocator_free(&state.output);
}

static void test_string_encodings(void) {
  const struct {
    const char *encoding;
    const char *input;
    const char *expected;
    unsigned conversions;
  } cases[] = {
    {"UTF-8", "Example.\xce\xb1", "Example.\xce\xb1", 0},
    {"US-ASCII", "main", "main", 0},
    {"UTF-8", "", "", 0},
    {"UTF-8", "\xff", "\xef\xbf\xbd", 0},
    {"US-ASCII", "\xff", "?", 0},
    {"ISO-8859-1", "caf\xe9", "caf\xc3\xa9", 1},
    {"ASCII-8BIT", "\xff", "\xef\xbf\xbd", 1},
  };
  virel_state state = {.output = miteruby_allocator_alloc(2048, "virel_test_encodings")};
  for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
    VALUE input = rb_enc_str_new(cases[i].input, strlen(cases[i].input), rb_enc_find(cases[i].encoding));
    rb_obj_freeze(input);
    state.output_size = encoding_calls = 0;
    write_string(&state, input);
    size_t length = strlen(cases[i].expected);
    assert(state.error == MITERUBY_SERIALIZER_OK && state.output_size == length + 2);
    assert(state.output[0] == 3 && state.output[1] == length);
    assert(memcmp(state.output + 2, cases[i].expected, length) == 0);
    assert(encoding_calls == cases[i].conversions);
    assert(RSTRING_LEN(input) == (long) strlen(cases[i].input));
    assert(memcmp(RSTRING_PTR(input), cases[i].input, RSTRING_LEN(input)) == 0);
    assert(rb_enc_get_index(input) == rb_enc_find_index(cases[i].encoding));
    RB_GC_GUARD(input);
  }
  miteruby_allocator_free(&state.output);
}

static void test_chunks(FILE *file) {
  VALUE serializer = serializer_new(serializer_class);
  const long times[] = {100, 200, 300, 300}, cpu[] = {50, 100, 140, 150};
  assert(prepare(serializer, 4, times, cpu) == MITERUBY_SERIALIZER_OK);
  finish(serializer);
  assert(get_state(serializer)->sample_count == 4);
  assert(get_state(serializer)->stack_count == 1);
  write_fixture(serializer, file);
  const long next_time[] = {400}, next_cpu[] = {200};
  assert(prepare(serializer, 1, next_time, next_cpu) == MITERUBY_SERIALIZER_OK);
  finish(serializer);
  write_fixture(serializer, file);
  assert(prepare(serializer, 0, NULL, NULL) == MITERUBY_SERIALIZER_OK);
  finish(serializer);
  write_fixture(serializer, file);
  const long missing_time[] = {500}, missing_cpu[] = {-1};
  assert(prepare(serializer, 1, missing_time, missing_cpu) == MITERUBY_SERIALIZER_OK);
  finish(serializer);
  write_fixture(serializer, file);
  const long restored_time[] = {600}, restored_cpu[] = {250};
  assert(prepare(serializer, 1, restored_time, restored_cpu) == MITERUBY_SERIALIZER_OK);
  finish(serializer);
  write_fixture(serializer, file);
  uint64_t old_writer = get_state(serializer)->writer_id;
  native_reset_after_fork(Qnil, serializer);
  assert(get_state(serializer)->writer_id != old_writer);
  assert(prepare(serializer, 1, restored_time, restored_cpu) == MITERUBY_SERIALIZER_OK);
  finish(serializer);
  write_fixture(serializer, file);
  RB_GC_GUARD(serializer);
}

static void test_errors(void) {
  VALUE serializer = serializer_new(serializer_class);
  fail_allocation = true;
  assert(prepare(serializer, 0, NULL, NULL) == MITERUBY_SERIALIZER_ALLOCATION_FAILED);
  fail_allocation = false;
  const long time[] = {1}, cpu[] = {2};
  fail_allocation = true;
  assert(prepare(serializer, 1, time, cpu) == MITERUBY_SERIALIZER_ALLOCATION_FAILED);
  fail_allocation = false;
  assert(prepare(serializer, 1, time, cpu) == MITERUBY_SERIALIZER_OK);
  virel_state *state = get_state(serializer);
  ((miteruby_event_deduped_sample_t *) state->events)->header.size_bytes = 0;
  assert(miteruby_virel_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_INVALID_EVENT);
  assert(state->status == VIREL_EMPTY && state->events == NULL);
  assert(prepare(serializer, 1, time, cpu) == MITERUBY_SERIALIZER_OK);
  ((miteruby_event_deduped_sample_t *) state->events)->stack.frame_count = 1;
  assert(miteruby_virel_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK);
  assert(prepare(serializer, 1, time, cpu) == MITERUBY_SERIALIZER_OK);
  state->output_size = VIREL_OUTPUT_CAPACITY;
  assert(miteruby_virel_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_VIREL_BUFFER_FULL);
  const long decreasing_times[] = {100, 99}, decreasing_cpu[] = {10, 20};
  assert(prepare(serializer, 2, decreasing_times, decreasing_cpu) == MITERUBY_SERIALIZER_OK);
  assert(miteruby_virel_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_INVALID_EVENT);
  assert(state->status == VIREL_EMPTY && state->events == NULL);
  assert(prepare(serializer, 1, time, cpu) == MITERUBY_SERIALIZER_OK);
  finish(serializer);
  assert(miteruby_virel_serializer_serialize_no_gvl(serializer) == MITERUBY_SERIALIZER_NOT_COMPLETED);
  native_serialize(Qnil, serializer);
  RB_GC_GUARD(serializer);
}

static VALUE serialize_in_thread(void *serializer) {
  finish((VALUE) serializer);
  return Qnil;
}

static void *wait_for_encoding(void *unused) {
  (void) unused;
  assert(mtx_lock(&gate_mutex) == thrd_success);
  while (!entered) assert(cnd_wait(&gate_condition, &gate_mutex) == thrd_success);
  assert(mtx_unlock(&gate_mutex) == thrd_success);
  return NULL;
}

static VALUE check_available(VALUE serializer) {
  miteruby_virel_serializer_check_available(serializer);
  return Qnil;
}

static VALUE reset(VALUE serializer) {
  return native_reset_after_fork(Qnil, serializer);
}

static void test_concurrency_and_fork(void) {
  assert(mtx_init(&gate_mutex, mtx_plain) == thrd_success);
  assert(cnd_init(&gate_condition) == thrd_success);
  VALUE serializer = serializer_new(serializer_class);
  assert(prepare(serializer, 0, NULL, NULL) == MITERUBY_SERIALIZER_OK);
  pause_encoding = true;
  VALUE thread = rb_thread_create(serialize_in_thread, (void *) serializer);
  rb_thread_call_without_gvl(wait_for_encoding, NULL, NULL, NULL);
  rb_gc_start();
  int error = 0;
  rb_protect(check_available, serializer, &error);
  assert(error != 0);
  rb_set_errinfo(Qnil);
  rb_protect(reset, serializer, &error);
  assert(error != 0);
  rb_set_errinfo(Qnil);
  pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    native_reset_after_fork(Qnil, serializer);
    _exit(get_state(serializer)->status == VIREL_EMPTY ? 0 : 1);
  }
  int status;
  assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
  assert(mtx_lock(&gate_mutex) == thrd_success);
  released = true;
  assert(cnd_broadcast(&gate_condition) == thrd_success);
  assert(mtx_unlock(&gate_mutex) == thrd_success);
  rb_funcall(thread, rb_intern("value"), 0);
  pause_encoding = false;
  assert(get_state(serializer)->status == VIREL_FINISHED);
  cnd_destroy(&gate_condition);
  mtx_destroy(&gate_mutex);
  RB_GC_GUARD(serializer);
}

int main(int argc, char **argv) {
  assert(argc == 2);
  FILE *fixture = fopen(argv[1], "wb");
  assert(fixture != NULL);
  ruby_sysinit(&argc, &argv);
  RUBY_INIT_STACK;
  ruby_init();
  char program[] = "virel-test", disable[] = "--disable=gems,rubyopt", eval[] = "-e", script[] = "";
  char *options[] = {program, disable, eval, script};
  assert(ruby_exec_node(ruby_options(4, options)) == 0);
  private_vm_api_access_init();
  VALUE profiling = rb_define_module_under(rb_define_module("Datadog"), "Profiling");
  miteruby_virel_serializer_init(profiling);
  serializer_class = rb_path2class("Datadog::Profiling::Miteruby::VirelSerializer");
  test_varints();
  test_string_boundary();
  test_string_encodings();
  test_chunks(fixture);
  test_errors();
  test_concurrency_and_fork();
  assert(fclose(fixture) == 0);
  puts("Virel serializer tests passed");
  return ruby_cleanup(0);
}
