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

static stack_key key_for(const miteruby_event_stack_sample_t *event) {
  return (stack_key) {
    .hash = vt_wyhash(event->refs, stack_data_size(event->header.frame_count)),
    .location.as.refs = event->refs,
    .frame_count = event->header.frame_count,
    .borrowed = true,
  };
}

static miteruby_event_frame_position_t *positions_for(miteruby_event_stack_sample_t *event) {
  return (miteruby_event_frame_position_t *)&event->refs[event->header.frame_count];
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
  size_t first = miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted);
  assert(inserted && first == 0);
  size_t used = unique_stacks_pos;
  sample_storage duplicate = storage;
  duplicate.event.header.timestamp.ns = 123;
  duplicate.event.header.cpu_time.ns = 456;
  duplicate.event.header.flags = MITERUBY_EVENT_STACK_TRUNCATED | MITERUBY_EVENT_FROM_SIGNAL_HANDLER;
  duplicate.event.thread.value = Qtrue;
  ((char *)duplicate.event.refs)[stack_data_size(2)] = 0xff;
  assert(miteruby_consumer_stack_dedup_get_or_insert(duplicate.event.refs, duplicate.event.header.frame_count, &inserted) == first && !inserted);
  assert(unique_stacks_pos == used);

  positions_for(event)[0].value++;
  size_t other_position = miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted);
  assert(inserted && other_position != first);
  event->refs[0].cme = NULL;
  size_t other_cme = miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted);
  assert(inserted && other_cme != other_position);
  event->refs[0].iseq = NULL;
  assert(miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted) != other_cme && inserted);
  event->header.frame_count = 1;
  assert(miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted) != first && inserted);

  stack_key collision = key_for(event);
  collision.hash = 42;
  size_t collision_first = deduplicate_stack(collision, &inserted);
  assert(inserted);
  positions_for(event)[0].value++;
  size_t collision_second = deduplicate_stack(collision, &inserted);
  assert(inserted && collision_first != collision_second);
  positions_for(event)[0].value--;
  assert(deduplicate_stack(collision, &inserted) == collision_first && !inserted);

  event->header.frame_count = 0;
  size_t empty = miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted);
  assert(inserted);
  assert(miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted) == empty && !inserted);
  assert(unique_stacks_pos > empty);
}

static void test_growth_and_relocation(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 3;
  size_t ids[20000];
  bool inserted;
  for (uint16_t i = 0; i < 20000; i++) {
    positions_for(event)[0].value = i;
    ids[i] = miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted);
    assert(inserted);
    assert(ids[i] % 8 == 0);
  }
  assert(unique_stacks_size > UNIQUE_STACKS_ARRAY_CHUNK_SIZE);

  char *relocated = malloc(unique_stacks_size);
  assert(relocated != NULL && relocated != unique_stacks_array);
  memcpy(relocated, unique_stacks_array, unique_stacks_pos);
  free(unique_stacks_array);
  unique_stacks_array = relocated;

  size_t used = unique_stacks_pos;
  for (uint16_t i = 0; i < 20000; i++) {
    positions_for(event)[0].value = i;
    assert(miteruby_consumer_stack_dedup_get_or_insert(event->refs, event->header.frame_count, &inserted) == ids[i] && !inserted);
  }
  assert(unique_stacks_pos == used);
  for (
    verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_first(&unique_stacks);
    !verstable_unique_stacks_map_is_end(entry);
    entry = verstable_unique_stacks_map_next(entry)
  ) {
    assert(!entry.data->key.borrowed);
    assert(entry.data->key.location.as.offset == entry.data->val);
  }
}

static void test_compact_events_and_reset(void) {
  miteruby_consumer_init();
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
  assert(verstable_unique_stacks_map_size(&unique_stacks) == 1);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == 3);
  assert(consumed_events_count == 30000);
  assert(consumed_events_capacity > CONSUMED_EVENTS_BUFFER_CHUNK_CAPACITY);
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
  assert(verstable_unique_stacks_map_size(&unique_stacks) == 1);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == 4);

  miteruby_consumer_init();
  assert(consumed_events_count == 0 && unique_stacks_pos == 0);
  assert(unique_stacks_size == 0 && unique_stacks_array == NULL);
  assert(verstable_unique_stacks_map_size(&unique_stacks) == 0);
  assert(verstable_objects_to_mark_set_size(&state.objects_to_mark) == 0);
  buffer_event(&event->header);
  assert(verstable_unique_stacks_map_size(&unique_stacks) == 1);
  assert(consumed_events_buffer[0].stack_id == 0);
}

int main(void) {
  initialize_mutexes();
  verstable_objects_to_mark_set_init(&state.objects_to_mark);
  miteruby_consumer_stack_dedup_init();
  test_identity_and_collisions();
  test_growth_and_relocation();
  test_compact_events_and_reset();
  verstable_unique_stacks_map_cleanup(&unique_stacks);
  verstable_objects_to_mark_set_cleanup(&state.objects_to_mark);
  assert(unique_stacks_map_allocated_bytes == 0 && objects_to_mark_allocated_bytes == 0);
  free(unique_stacks_array);
  free(consumed_events_buffer);
  mtx_destroy(&consumed_events_mutex);
  mtx_destroy(&objects_to_mark_mutex);
  puts("Miteruby consumer tests passed");
  return 0;
}
