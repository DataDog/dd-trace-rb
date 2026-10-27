#include "../../../ext/datadog_profiling_native_extension/miteruby/consumer_stack_dedup.c"
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

static void test_empty_stack_before_nonempty(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  bool inserted;
  assert(miteruby_consumer_stack_dedup_get_or_insert((miteruby_event_stack_sample_view_t) {0}, &inserted) == 0 && inserted);
  assert(miteruby_consumer_stack_dedup_get_or_insert((miteruby_event_stack_sample_view_t) {0}, &inserted) == 0 && !inserted);
  assert(stack_dedup_state.unique_stacks_pos == 8);
  assert(miteruby_consumer_stack_dedup_get(0).frame_count == 0);

  event->header.frame_count = 1;
  positions_for(event)[0].value = 7;
  assert(miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted) == 8 && inserted);
  assert(stack_dedup_state.unique_stacks_pos == 40);
  miteruby_event_stack_sample_view_t stored = miteruby_consumer_stack_dedup_get(8);
  assert(stored.frame_count == 1);
  assert(stored.positions[0].value == 7);
  assert(memcmp(stored.refs, event->refs, sizeof(*event->refs)) == 0);
  assert(miteruby_consumer_stack_dedup_get_or_insert((miteruby_event_stack_sample_view_t) {0}, &inserted) == 0 && !inserted);
  assert(miteruby_consumer_stack_dedup_get(0).frame_count == 0);
  assert(miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted) == 8 && !inserted);
  assert(stack_dedup_state.unique_stacks_pos == 40);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 2);
  miteruby_consumer_stack_dedup_reset();
}

static void test_identity_and_collisions(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 2;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->refs[0].iseq = (const rb_iseq_t *)&storage.words[15];
  positions_for(event)[0].value = 12;
  positions_for(event)[1].value = UINT16_MAX;

  bool inserted;
  size_t first = miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted);
  assert(inserted && first == 0);
  size_t used = stack_dedup_state.unique_stacks_pos;
  assert(used == 48);
  size_t data_size = 2 * (sizeof(miteruby_event_frame_refs_t) + sizeof(miteruby_event_frame_position_t));
  assert(memcmp(miteruby_consumer_stack_dedup_get(first).refs, event->refs, data_size) == 0);
  sample_storage duplicate = storage;
  duplicate.event.header.timestamp.ns = 123;
  duplicate.event.header.cpu_time.ns = 456;
  duplicate.event.header.flags = MITERUBY_EVENT_STACK_TRUNCATED | MITERUBY_EVENT_FROM_SIGNAL_HANDLER;
  duplicate.event.thread.value = Qtrue;
  ((char *)duplicate.event.refs)[data_size] = 0xff;
  assert(miteruby_consumer_stack_dedup_get_or_insert(view_for(&duplicate.event), &inserted) == first && !inserted);
  assert(stack_dedup_state.unique_stacks_pos == used);

  positions_for(event)[0].value++;
  size_t other_position = miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted);
  assert(inserted && other_position != first);
  event->refs[0].cme = NULL;
  size_t other_cme = miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted);
  assert(inserted && other_cme != other_position);
  event->refs[0].iseq = NULL;
  assert(miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted) != other_cme && inserted);
  event->header.frame_count = 1;
  assert(miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted) != first && inserted);

  miteruby_event_stack_sample_view_t collision_view = view_for(&duplicate.event);
  stack_key collision = key_for(&collision_view);
  collision.hash = 42;
  stack_key stored_collision = {.hash = 42, .location.as.offset = first, .view_borrowed = false};
  assert(stack_key_equal(collision, stored_collision));
  collision_view.positions[0].value++;
  assert(!stack_key_equal(collision, stored_collision));
  collision_view.positions[0].value--;
  assert(stack_key_equal(collision, stored_collision));
  stored_collision.location.as.offset = other_cme;
  assert(!stack_key_equal(collision, stored_collision));
  stored_collision.location.as.offset = first;
  collision_view.frame_count = 1;
  assert(!stack_key_equal(collision, stored_collision));
  collision_view.frame_count = 0;
  assert(!stack_key_equal(collision, stored_collision));

  event->header.frame_count = 0;
  used = stack_dedup_state.unique_stacks_pos;
  size_t empty = miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted);
  assert(inserted && empty == used);
  assert(miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted) == empty && !inserted);
  assert(stack_dedup_state.unique_stacks_pos == used + 8);
  assert(miteruby_consumer_stack_dedup_get(empty).frame_count == 0);
  assert(miteruby_consumer_stack_dedup_get(first).frame_count == 2);
  stored_collision.location.as.offset = empty;
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
  bool inserted;
  size_t stack_id = miteruby_consumer_stack_dedup_get_or_insert(input, &inserted);
  assert(inserted);
  miteruby_event_stack_sample_view_t stored = miteruby_consumer_stack_dedup_get(stack_id);
  assert(stored.frame_count == 2);
  assert(memcmp(stored.refs, input.refs, 2 * sizeof(*input.refs)) == 0);
  assert(memcmp(stored.positions, positions, sizeof(positions)) == 0);

  memcpy(positions_for(event), positions, sizeof(positions));
  assert(miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted) == stack_id && !inserted);
  positions[0].value++;
  assert(stored.positions[0].value == 19);
  assert(miteruby_consumer_stack_dedup_get_or_insert(input, &inserted) != stack_id && inserted);
  positions[0].value--;
  assert(miteruby_consumer_stack_dedup_get_or_insert(input, &inserted) == stack_id && !inserted);
}

static void test_growth_and_relocation(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 3;
  size_t ids[20000];
  bool inserted;
  for (uint16_t i = 0; i < 20000; i++) {
    positions_for(event)[0].value = i;
    ids[i] = miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted);
    assert(inserted);
    assert(ids[i] % 8 == 0);
  }
  assert(stack_dedup_state.unique_stacks_size > UNIQUE_STACKS_ARRAY_CHUNK_SIZE);
  assert(stack_dedup_state.unique_stacks_set_allocated_bytes > 0);
  assert_allocation_accounting();

  uint8_t *relocated = miteruby_allocator_alloc(stack_dedup_state.unique_stacks_size, "unique_stacks_array");
  assert(relocated != NULL && relocated != stack_dedup_state.unique_stacks_array);
  memcpy(relocated, stack_dedup_state.unique_stacks_array, stack_dedup_state.unique_stacks_pos);
  miteruby_allocator_free(stack_dedup_state.unique_stacks_array, stack_dedup_state.unique_stacks_size);
  stack_dedup_state.unique_stacks_array = relocated;
  assert_allocation_accounting();

  size_t used = stack_dedup_state.unique_stacks_pos;
  for (uint16_t i = 0; i < 20000; i++) {
    positions_for(event)[0].value = i;
    assert(miteruby_consumer_stack_dedup_get_or_insert(view_for(event), &inserted) == ids[i] && !inserted);
    miteruby_event_stack_sample_view_t stored = miteruby_consumer_stack_dedup_get(ids[i]);
    assert(stored.frame_count == 3);
    assert(stored.positions[0].value == i);
    assert(memcmp(stored.refs, event->refs, 3 * sizeof(*event->refs)) == 0);
  }
  assert(stack_dedup_state.unique_stacks_pos == used);
  size_t empty = miteruby_consumer_stack_dedup_get_or_insert((miteruby_event_stack_sample_view_t) {0}, &inserted);
  assert(!inserted && miteruby_consumer_stack_dedup_get(empty).frame_count == 0);
  for (
    verstable_unique_stacks_set_itr entry = verstable_unique_stacks_set_first(&stack_dedup_state.unique_stacks);
    !verstable_unique_stacks_set_is_end(entry);
    entry = verstable_unique_stacks_set_next(entry)
  ) {
    assert(!entry.data->key.view_borrowed);
    assert(entry.data->key.location.as.offset < used);
  }
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
    buffer_event(&event->header);
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
    assert(deduped->thread.value == Qnil && deduped->stack_id == 0);
  }

  miteruby_event_overflow_t overflow = {.header = {.type = MITERUBY_EVENT_OVERFLOW, .size_bytes = sizeof(overflow)}};
  size_t previous_count = consumed_events_count;
  buffer_event(&overflow.header);
  assert(consumed_events_count == previous_count);
  overflow.header.type = MITERUBY_EVENT_INVALID;
  buffer_event(&overflow.header);
  assert(consumed_events_count == previous_count);

  consumed_events_count = 0;
  event->thread.value = Qtrue;
  buffer_event(&event->header);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 1);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == 4);

  miteruby_consumer_init();
  assert_allocation_accounting();
  assert(consumed_events_count == 0 && stack_dedup_state.unique_stacks_pos == 0);
  assert(stack_dedup_state.unique_stacks_size == UNIQUE_STACKS_ARRAY_CHUNK_SIZE && stack_dedup_state.unique_stacks_array != NULL);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 0);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == 0);
  buffer_event(&event->header);
  assert(verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) == 1);
  assert(consumed_events_buffer[0].stack_id == 0);
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
  miteruby_consumer_stack_dedup_init();
  assert(stack_dedup_state.unique_stacks_size == UNIQUE_STACKS_ARRAY_CHUNK_SIZE && stack_dedup_state.unique_stacks_array != NULL);
  assert_allocation_accounting();
  test_empty_stack_before_nonempty();
  test_identity_and_collisions();
  test_separate_arrays();
  test_growth_and_relocation();
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
