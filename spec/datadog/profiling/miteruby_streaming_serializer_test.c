#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"
#include <stdbool.h>

static bool fail_allocations;

static void *test_allocator_alloc(size_t size, const char *name) {
  return fail_allocations ? NULL : miteruby_allocator_alloc(size, name);
}

#define miteruby_allocator_alloc test_allocator_alloc
#include "../../../ext/datadog_profiling_native_extension/miteruby/streaming_serializer.c"
#undef miteruby_allocator_alloc

#undef NDEBUG
#include <assert.h>

static void test_sample_values(void) {
  verstable_streaming_thread_contexts_map contexts;
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

  verstable_streaming_thread_contexts_map_init(&contexts);
  size_t allocated_bytes = 0;
  for (int serialization = 0; serialization < 2; serialization++) {
    verstable_streaming_thread_contexts_map_clear(&contexts);
    if (serialization == 1) {
      for (int thread = 1; thread <= 2; thread++) {
        streaming_thread_context *context = thread_context_for(&contexts, INT2FIX(thread));
        context->thread_name_string_id = 22 + thread * 2;
        context->thread_id_string_id = context->thread_name_string_id + 1;
        assert(!context->has_previous_sample);
      }
    }
    for (size_t i = 0; i < sizeof(samples) / sizeof(samples[0]); i++) {
      miteruby_event_deduped_sample_t event = {
        .header = {.cpu_time = {.ns = samples[i].cpu}, .timestamp = {.ns = samples[i].monotonic}},
      };
      miteruby_sample_values values = sample_values_for(&contexts, INT2FIX(samples[i].thread), &event);
      assert(values.cpu_time_ns == samples[i].expected_cpu);
      assert(values.wall_time_ns == samples[i].expected_wall);
      assert(values.cpu_or_wall_samples == 1);
      assert(values.alloc_samples == 0 && values.alloc_samples_unscaled == 0 && values.timeline_wall_time_ns == 0);
      streaming_thread_context *context = thread_context_for(&contexts, INT2FIX(samples[i].thread));
      assert(context->has_previous_sample);
      if (serialization == 1) {
        assert(context->thread_name_string_id == 22 + samples[i].thread * 2);
        assert(context->thread_id_string_id == context->thread_name_string_id + 1);
      }
    }
    assert(verstable_streaming_thread_contexts_map_size(&contexts) == 2);
    if (serialization == 0) allocated_bytes = miteruby_allocator_requested_bytes();
    else assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  }
  verstable_streaming_thread_contexts_map_cleanup(&contexts);
  assert(miteruby_allocator_requested_bytes() == 0);
}

static VALUE exhaust_contexts(VALUE contexts_ptr) {
  verstable_streaming_thread_contexts_map *contexts = (verstable_streaming_thread_contexts_map *) contexts_ptr;
  miteruby_event_deduped_sample_t event = {0};
  sample_values_for(contexts, INT2FIX(0), &event);
  fail_allocations = true;
  for (int i = 1; i < 100; i++) sample_values_for(contexts, INT2FIX(i), &event);
  assert(false);
  return Qnil;
}

static void test_reuse_after_error(void) {
  verstable_streaming_thread_contexts_map contexts;
  verstable_streaming_thread_contexts_map_init(&contexts);
  int error = 0;
  rb_protect(exhaust_contexts, (VALUE) &contexts, &error);
  assert(error != 0 && RTEST(rb_obj_is_kind_of(rb_errinfo(), rb_eRuntimeError)));
  assert(verstable_streaming_thread_contexts_map_size(&contexts) > 0);
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  verstable_streaming_thread_contexts_map_clear(&contexts);
  miteruby_event_deduped_sample_t event = {.header = {.cpu_time = {.ns = 100}, .timestamp = {.ns = 200}}};
  miteruby_sample_values values = sample_values_for(&contexts, INT2FIX(0), &event);
  assert(values.cpu_time_ns == 0 && values.wall_time_ns == 0);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  fail_allocations = false;
  verstable_streaming_thread_contexts_map_cleanup(&contexts);
  assert(miteruby_allocator_requested_bytes() == 0);
  rb_set_errinfo(Qnil);
}

int main(int argc, char **argv) {
  ruby_sysinit(&argc, &argv);
  RUBY_INIT_STACK;
  ruby_init();
  test_sample_values();
  test_reuse_after_error();
  puts("Miteruby streaming serializer tests passed");
  return ruby_cleanup(0);
}
