#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"
#include <string.h>

static const char *failed_allocation_name;

static void *test_allocator_alloc(size_t size, const char *name) {
  if (failed_allocation_name != NULL && strcmp(name, failed_allocation_name) == 0) return NULL;
  return miteruby_allocator_alloc(size, name);
}

#define miteruby_allocator_alloc test_allocator_alloc
#include "../../../ext/datadog_profiling_native_extension/miteruby/stack_dedup.c"
#undef miteruby_allocator_alloc
#include "../../../ext/datadog_profiling_native_extension/miteruby/consumer.c"

#undef NDEBUG
#include <assert.h>
#include <stdio.h>

void miteruby_consumer_recorder_init(void) {}
__attribute__((noreturn)) void miteruby_buffer_mark(DDTRACE_UNUSED miteruby_buffer_t *buffer) { abort(); }

typedef union {
  miteruby_event_stack_sample_t event;
  uint64_t words[16];
} sample_storage;

static stack_key key_for(const miteruby_event_stack_sample_view_t *view) {
  return (stack_key) {
    .hash = stack_view_hash(*view),
    .location.as.view = view,
    .view_borrowed = true,
  };
}

static miteruby_event_frame_position_t *positions_for(miteruby_event_stack_sample_t *event) {
  return (miteruby_event_frame_position_t *)&event->refs[event->header.frame_count];
}

static miteruby_event_stack_sample_view_t view_for(miteruby_event_stack_sample_t *event) {
  return (miteruby_event_stack_sample_view_t) {
    .refs = event->refs,
    .positions = positions_for(event),
    .frame_count = event->header.frame_count,
  };
}

static void assert_allocation_accounting(void) {
  assert(miteruby_allocator_requested_bytes() ==
    objects_to_mark_allocated_bytes + stack_dedup_state.unique_stacks_set_allocated_bytes + stack_dedup_state.unique_stacks_size +
    consumed_events_capacity * sizeof(*consumed_events_buffer));
}

static miteruby_stack_dedup_id_t assert_dedup(miteruby_event_stack_sample_view_t view, bool inserted) {
  miteruby_stack_dedup_result_t result = miteruby_stack_dedup_get_or_insert(view);
  assert(!result.error_storage_full);
  assert(result.ok.inserted == inserted);
  return result.ok.id;
}

static void test_empty_stack_before_nonempty(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  assert(assert_dedup((miteruby_event_stack_sample_view_t) {0}, true).offset == 0);
  assert(assert_dedup((miteruby_event_stack_sample_view_t) {0}, false).offset == 0);
  assert(stack_dedup_state.unique_stacks_pos == 8);
  assert(miteruby_stack_dedup_get((miteruby_stack_dedup_id_t) {.offset = 0}).frame_count == 0);

  event->header.frame_count = 1;
  positions_for(event)[0].value = 7;
  assert(assert_dedup(view_for(event), true).offset == 8);
  assert(stack_dedup_state.unique_stacks_pos == 40);
  miteruby_event_stack_sample_view_t stored = miteruby_stack_dedup_get((miteruby_stack_dedup_id_t) {.offset = 8});
  assert(stored.frame_count == 1);
  assert(stored.positions[0].value == 7);
  assert(memcmp(stored.refs, event->refs, sizeof(*event->refs)) == 0);
  assert(assert_dedup((miteruby_event_stack_sample_view_t) {0}, false).offset == 0);
  assert(miteruby_stack_dedup_get((miteruby_stack_dedup_id_t) {.offset = 0}).frame_count == 0);
  assert(assert_dedup(view_for(event), false).offset == 8);
  assert(stack_dedup_state.unique_stacks_pos == 40);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 2);
  miteruby_stack_dedup_reset();
}

static void test_identity_and_collisions(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 2;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->refs[0].iseq = (const rb_iseq_t *)&storage.words[15];
  positions_for(event)[0].value = 12;
  positions_for(event)[1].value = UINT16_MAX;

  miteruby_stack_dedup_id_t first = assert_dedup(view_for(event), true);
  assert(first.offset == 0);
  size_t used = stack_dedup_state.unique_stacks_pos;
  assert(used == 48);
  size_t data_size = 2 * (sizeof(miteruby_event_frame_refs_t) + sizeof(miteruby_event_frame_position_t));
  assert(memcmp(miteruby_stack_dedup_get(first).refs, event->refs, data_size) == 0);
  sample_storage duplicate = storage;
  duplicate.event.header.timestamp.ns = 123;
  duplicate.event.header.cpu_time.ns = 456;
  duplicate.event.header.flags = MITERUBY_EVENT_STACK_TRUNCATED | MITERUBY_EVENT_FROM_SIGNAL_HANDLER;
  duplicate.event.thread.value = Qtrue;
  ((char *)duplicate.event.refs)[data_size] = 0xff;
  assert(assert_dedup(view_for(&duplicate.event), false).offset == first.offset);
  assert(stack_dedup_state.unique_stacks_pos == used);

  positions_for(event)[0].value++;
  miteruby_stack_dedup_id_t other_position = assert_dedup(view_for(event), true);
  assert(other_position.offset != first.offset);
  event->refs[0].cme = NULL;
  miteruby_stack_dedup_id_t other_cme = assert_dedup(view_for(event), true);
  assert(other_cme.offset != other_position.offset);
  event->refs[0].iseq = NULL;
  assert(assert_dedup(view_for(event), true).offset != other_cme.offset);
  event->header.frame_count = 1;
  assert(assert_dedup(view_for(event), true).offset != first.offset);

  miteruby_event_stack_sample_view_t collision_view = view_for(&duplicate.event);
  stack_key collision = key_for(&collision_view);
  collision.hash = 42;
  stack_key stored_collision = {.hash = 42, .location.as.stack_id = first, .view_borrowed = false};
  assert(stack_key_equal(collision, stored_collision));
  collision_view.positions[0].value++;
  assert(!stack_key_equal(collision, stored_collision));
  collision_view.positions[0].value--;
  assert(stack_key_equal(collision, stored_collision));
  stored_collision.location.as.stack_id = other_cme;
  assert(!stack_key_equal(collision, stored_collision));
  stored_collision.location.as.stack_id = first;
  collision_view.frame_count = 1;
  assert(!stack_key_equal(collision, stored_collision));
  collision_view.frame_count = 0;
  assert(!stack_key_equal(collision, stored_collision));

  event->header.frame_count = 0;
  used = stack_dedup_state.unique_stacks_pos;
  miteruby_stack_dedup_id_t empty = assert_dedup(view_for(event), true);
  assert(empty.offset == used);
  assert(assert_dedup(view_for(event), false).offset == empty.offset);
  assert(stack_dedup_state.unique_stacks_pos == used + 8);
  assert(miteruby_stack_dedup_get(empty).frame_count == 0);
  assert(miteruby_stack_dedup_get(first).frame_count == 2);
  stored_collision.location.as.stack_id = empty;
  assert(stack_key_equal(collision, stored_collision));
}

static void test_separate_arrays(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 2;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->refs[1].iseq = (const rb_iseq_t *)&storage.words[15];
  miteruby_event_frame_position_t positions[] = {{.value = 19}, {.value = 27}};
  miteruby_event_stack_sample_view_t input = {.refs = event->refs, .positions = positions, .frame_count = 2};
  miteruby_stack_dedup_id_t stack_id = assert_dedup(input, true);
  miteruby_event_stack_sample_view_t stored = miteruby_stack_dedup_get(stack_id);
  assert(stored.frame_count == 2);
  assert(memcmp(stored.refs, input.refs, 2 * sizeof(*input.refs)) == 0);
  assert(memcmp(stored.positions, positions, sizeof(positions)) == 0);

  memcpy(positions_for(event), positions, sizeof(positions));
  assert(assert_dedup(view_for(event), false).offset == stack_id.offset);
  positions[0].value++;
  assert(stored.positions[0].value == 19);
  assert(assert_dedup(input, true).offset != stack_id.offset);
  positions[0].value--;
  assert(assert_dedup(input, false).offset == stack_id.offset);
}

static void test_set_growth_and_stable_storage(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 3;
  uint8_t *array = stack_dedup_state.unique_stacks_array;
  miteruby_stack_dedup_id_t ids[20000];
  for (uint16_t i = 0; i < 20000; i++) {
    positions_for(event)[0].value = i;
    ids[i] = assert_dedup(view_for(event), true);
    assert(ids[i].offset % 8 == 0);
  }
  assert(stack_dedup_state.unique_stacks_size == UNIQUE_STACKS_ARRAY_MAX_SIZE);
  assert(stack_dedup_state.unique_stacks_array == array);
  assert(stack_dedup_state.unique_stacks_set_allocated_bytes > 0);
  assert_allocation_accounting();

  size_t used = stack_dedup_state.unique_stacks_pos;
  for (uint16_t i = 0; i < 20000; i++) {
    positions_for(event)[0].value = i;
    assert(assert_dedup(view_for(event), false).offset == ids[i].offset);
    miteruby_event_stack_sample_view_t stored = miteruby_stack_dedup_get(ids[i]);
    assert(stored.frame_count == 3);
    assert(stored.positions[0].value == i);
    assert(memcmp(stored.refs, event->refs, 3 * sizeof(*event->refs)) == 0);
  }
  assert(stack_dedup_state.unique_stacks_pos == used);
  miteruby_stack_dedup_id_t empty = assert_dedup((miteruby_event_stack_sample_view_t) {0}, false);
  assert(miteruby_stack_dedup_get(empty).frame_count == 0);
  for (
    verstable_unique_stacks_set_itr entry = verstable_unique_stacks_set_first(&stack_dedup_state.unique_stacks);
    !verstable_unique_stacks_set_is_end(entry);
    entry = verstable_unique_stacks_set_next(entry)
  ) {
    assert(!entry.data->key.view_borrowed);
    assert(entry.data->key.location.as.stack_id.offset < used);
  }
}

static void assert_failed_dedup(miteruby_event_stack_sample_view_t view) {
  size_t count = verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks);
  size_t pos = stack_dedup_state.unique_stacks_pos;
  uint8_t *array = stack_dedup_state.unique_stacks_array;
  assert(miteruby_stack_dedup_get_or_insert(view).error_storage_full);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == count);
  assert(stack_dedup_state.unique_stacks_pos == pos);
  assert(stack_dedup_state.unique_stacks_array == array);
  for (
    verstable_unique_stacks_set_itr entry = verstable_unique_stacks_set_first(&stack_dedup_state.unique_stacks);
    !verstable_unique_stacks_set_is_end(entry);
    entry = verstable_unique_stacks_set_next(entry)
  ) {
    assert(!entry.data->key.view_borrowed);
  }
}

static void test_dedup_errors(void) {
  miteruby_stack_dedup_reset();
  verstable_unique_stacks_set_cleanup(&stack_dedup_state.unique_stacks);
  verstable_unique_stacks_set_init(&stack_dedup_state.unique_stacks);
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 1;

  failed_allocation_name = "unique_stacks_set";
  assert_failed_dedup(view_for(event));
  failed_allocation_name = NULL;
  assert(assert_dedup(view_for(event), true).offset == 0);
  assert_allocation_accounting();
}

static void test_fixed_array_capacity(void) {
  miteruby_stack_dedup_reset();
  uint8_t *array = stack_dedup_state.unique_stacks_array;
  miteruby_event_frame_refs_t refs[1024] = {0};
  miteruby_event_frame_position_t positions[1024] = {0};
  miteruby_event_stack_sample_view_t view = {.refs = refs, .positions = positions, .frame_count = 1024};
  miteruby_stack_dedup_id_t first = assert_dedup(view, true);
  miteruby_event_stack_sample_view_t stored = miteruby_stack_dedup_get(first);
  size_t record_size = stack_dedup_state.unique_stacks_pos;
  uint16_t position = 1;
  while (UNIQUE_STACKS_ARRAY_MAX_SIZE - stack_dedup_state.unique_stacks_pos >= record_size) {
    positions[0].value = position++;
    assert_dedup(view, true);
  }

  positions[0].value = position;
  assert_failed_dedup(view);
  size_t remaining = UNIQUE_STACKS_ARRAY_MAX_SIZE - stack_dedup_state.unique_stacks_pos;
  view.frame_count = (remaining - sizeof(miteruby_stack_t)) / (sizeof(*refs) + sizeof(*positions));
  assert_dedup(view, true);
  assert(stack_dedup_state.unique_stacks_pos == 16U * 1024U * 1024U);
  assert(stack_dedup_state.unique_stacks_size == 16U * 1024U * 1024U);
  assert(stack_dedup_state.unique_stacks_array == array);
  assert_failed_dedup((miteruby_event_stack_sample_view_t) {0});

  sample_storage storage = {0};
  storage.event.header.type = MITERUBY_EVENT_STACK_SAMPLE;
  storage.event.thread.value = Qtrue;
  size_t previous_events_count = consumed_events_count;
  size_t previous_objects_count = verstable_objects_to_mark_set_size(&state.objects_to_mark);
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_DEDUP_STORAGE_FULL);
  assert(consumed_events_count == previous_events_count);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == previous_objects_count);

  view.frame_count = 1024;
  assert_failed_dedup(view);
  positions[0].value = 0;
  assert(assert_dedup(view, false).offset == first.offset);
  assert(stored.refs == miteruby_stack_dedup_get(first).refs);
  assert(stored.positions[0].value == 0);
  assert_allocation_accounting();

  miteruby_stack_dedup_reset();
  assert(assert_dedup(view, true).offset == 0);
  assert_allocation_accounting();
}

static void test_compact_events_and_reset(void) {
  miteruby_consumer_init();
  assert_allocation_accounting();
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header = (miteruby_event_header_t) {
    .type = MITERUBY_EVENT_STACK_SAMPLE,
    .size_bytes = 72,
    .frame_count = 2,
    .flags = MITERUBY_EVENT_STACK_TRUNCATED | MITERUBY_EVENT_FROM_SIGNAL_HANDLER,
    .timestamp.ns = 123,
    .cpu_time.ns = 456,
  };
  event->thread.value = Qnil;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->refs[0].iseq = (const rb_iseq_t *)&storage.words[15];
  for (size_t i = 0; i < 30000; i++) {
    event->header.timestamp.ns = 123 + i;
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  }
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 1);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == 3);
  assert(consumed_events_count == 30000);
  assert(consumed_events_capacity > CONSUMED_EVENTS_BUFFER_CHUNK_CAPACITY);
  assert(objects_to_mark_allocated_bytes > 0);
  assert_allocation_accounting();
  for (size_t i = 0; i < 30000; i++) {
    const miteruby_event_deduped_sample_t *deduped = &consumed_events_buffer[i];
    assert(deduped->header.type == MITERUBY_EVENT_DEDUPED_SAMPLE);
    assert(deduped->header.size_bytes == sizeof(*deduped));
    assert(deduped->header.frame_count == 2);
    assert(deduped->header.flags == event->header.flags);
    assert(deduped->header.timestamp.ns == (long)(123 + i));
    assert(deduped->header.cpu_time.ns == 456);
    assert(deduped->thread.value == Qnil && deduped->stack_id.offset == 0);
  }

  miteruby_event_overflow_t overflow = {.header = {.type = MITERUBY_EVENT_OVERFLOW, .size_bytes = sizeof(overflow)}};
  size_t previous_count = consumed_events_count;
  assert(buffer_event(&overflow.header) == MITERUBY_CONSUMER_OK);
  assert(consumed_events_count == previous_count);
  overflow.header.type = MITERUBY_EVENT_INVALID;
  assert(buffer_event(&overflow.header) == MITERUBY_CONSUMER_OK);
  assert(consumed_events_count == previous_count);

  consumed_events_count = 0;
  event->thread.value = Qtrue;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 1);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == 4);

  miteruby_consumer_init();
  assert_allocation_accounting();
  assert(consumed_events_count == 0 && stack_dedup_state.unique_stacks_pos == 0);
  assert(stack_dedup_state.unique_stacks_size == UNIQUE_STACKS_ARRAY_MAX_SIZE && stack_dedup_state.unique_stacks_array != NULL);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 0);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == 0);
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 1);
  assert(consumed_events_buffer[0].stack_id.offset == 0);
}

static void test_objects_to_mark_growth(void) {
  size_t initial_size = objects_to_mark_allocated_bytes;
  for (size_t i = 0; i < 20000; i++) retain_object((VALUE)i);
  assert(objects_to_mark_allocated_bytes > initial_size);
  assert_allocation_accounting();
  for (size_t i = 0; i < 20000; i++) {
    assert(!verstable_objects_to_mark_set_is_end(verstable_objects_to_mark_set_get(&state.objects_to_mark, (VALUE)i)));
  }
}

int main(void) {
  initialize_mutexes();
  verstable_objects_to_mark_set_init(&state.objects_to_mark);
  miteruby_stack_dedup_init();
  assert(stack_dedup_state.unique_stacks_size == UNIQUE_STACKS_ARRAY_MAX_SIZE && stack_dedup_state.unique_stacks_array != NULL);
  assert_allocation_accounting();
  test_empty_stack_before_nonempty();
  test_identity_and_collisions();
  test_separate_arrays();
  test_set_growth_and_stable_storage();
  test_dedup_errors();
  test_fixed_array_capacity();
  test_compact_events_and_reset();
  test_objects_to_mark_growth();
  verstable_unique_stacks_set_cleanup(&stack_dedup_state.unique_stacks);
  verstable_objects_to_mark_set_cleanup(&state.objects_to_mark);
  assert(stack_dedup_state.unique_stacks_set_allocated_bytes == 0 && objects_to_mark_allocated_bytes == 0);
  miteruby_allocator_free(stack_dedup_state.unique_stacks_array, stack_dedup_state.unique_stacks_size);
  miteruby_allocator_free(consumed_events_buffer, consumed_events_capacity * sizeof(*consumed_events_buffer));
  assert(miteruby_allocator_requested_bytes() == 0);
  mtx_destroy(&consumed_events_mutex);
  mtx_destroy(&objects_to_mark_mutex);
  puts("Miteruby consumer tests passed");
  return 0;
}
