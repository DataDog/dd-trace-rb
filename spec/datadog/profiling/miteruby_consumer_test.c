#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"
#include <string.h>

static const char *failed_allocation_name;

static void *test_allocator_alloc(size_t size, const char *name) {
  if (failed_allocation_name != NULL && strcmp(name, failed_allocation_name) == 0) return NULL;
  return miteruby_allocator_alloc(size, name);
}

#define miteruby_allocator_alloc test_allocator_alloc
#include "../../../ext/datadog_profiling_native_extension/miteruby/stack_dedup.c"
#include "../../../ext/datadog_profiling_native_extension/miteruby/consumer.c"
#include "../../../ext/datadog_profiling_native_extension/miteruby/consumer_recorder.c"
#undef miteruby_allocator_alloc

#undef NDEBUG
#include <assert.h>
#include <stdio.h>

__attribute__((noreturn)) void miteruby_raw_events_queue_mark(DDTRACE_UNUSED miteruby_raw_events_queue_t *raw_events_queue) {
  rb_bug("Unexpected miteruby_raw_events_queue_mark call in consumer test");
}

typedef union {
  miteruby_event_stack_sample_t event;
  uint64_t words[16];
} sample_storage;

static miteruby_event_frame_position_t *positions_for(miteruby_event_stack_sample_t *event) {
  return (miteruby_event_frame_position_t *)&event->refs[event->header.frame_count];
}

static void assert_allocation_accounting(void) {
  assert(miteruby_allocator_requested_bytes() ==
    miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets) +
    miteruby_allocator_alloc_size(consumer_state.mark_cme_iseq_map.buckets) +
    miteruby_allocator_alloc_size(consumer_state.location_map.buckets) +
    miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets) +
    miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) +
    consumer_state.interned_events_capacity * sizeof(*consumer_state.interned_events_queue));
  assert(consumer_size(&consumer_state) == sizeof(consumer_state) + sizeof(*consumer_state.raw_events_queue) +
    sizeof(stack_dedup_state.unique_stacks) + miteruby_allocator_requested_bytes());
}

static VALUE initialize_consumer(DDTRACE_UNUSED VALUE unused) {
  miteruby_consumer_init(NULL);
  return Qnil;
}

static VALUE reset_consumer(DDTRACE_UNUSED VALUE unused) {
  miteruby_consumer_reset();
  return Qnil;
}

static void assert_runtime_error(VALUE (*operation)(VALUE), const char *message) {
  int status = 0;
  rb_protect(operation, Qnil, &status);
  assert(status != 0);
  VALUE error = rb_errinfo();
  assert(rb_obj_is_kind_of(error, rb_eRuntimeError));
  VALUE actual_message = rb_funcall(error, rb_intern("message"), 0);
  assert(strcmp(StringValueCStr(actual_message), message) == 0);
  rb_set_errinfo(Qnil);
}

static void test_initialization_failure(void) {
  failed_allocation_name = "unique_stacks_array";
  assert(!miteruby_stack_dedup_init());
  assert_runtime_error(initialize_consumer, "Failure during miteruby_stack_dedup_init");
  assert(stack_dedup_state.unique_stacks_array == NULL);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) == 0);
  assert(stack_dedup_state.unique_stacks_pos == 0);
  assert(miteruby_allocator_requested_bytes() == 0);
  failed_allocation_name = NULL;
}

static int check_consumer_mutex_unlocked(DDTRACE_UNUSED void *unused) {
  assert(mtx_trylock(&consumer_state.mutex) == thrd_success);
  assert(mtx_unlock(&consumer_state.mutex) == thrd_success);
  return 0;
}

static void test_reset_failure(const char *allocation, const char *message) {
  miteruby_consumer_reset();
  sample_storage storage = {0};
  storage.event.header.type = MITERUBY_EVENT_STACK_SAMPLE;
  storage.event.header.frame_count = 1;
  storage.event.thread.value = Qnil;
  storage.event.refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  storage.event.refs[0].iseq = (const rb_iseq_t *)&storage.words[15];
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_OK);

  miteruby_event_deduped_sample_t *queue = consumer_state.interned_events_queue;
  size_t events_count = consumer_state.interned_events_count;
  size_t capacity = consumer_state.interned_events_capacity;
  size_t cme_iseq_count = verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map);
  size_t threads_count = verstable_mark_threads_set_size(&consumer_state.mark_threads_set);
  uint8_t *array = stack_dedup_state.unique_stacks_array;
  size_t pos = stack_dedup_state.unique_stacks_pos;
  size_t stacks_count = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks);
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  assert(events_count > 0 && stacks_count > 0 && threads_count > 0 && cme_iseq_count > 0);

  failed_allocation_name = allocation;
  assert_runtime_error(reset_consumer, message);
  failed_allocation_name = NULL;

  assert(consumer_state.interned_events_queue == queue);
  assert(consumer_state.interned_events_count == 0);
  assert(consumer_state.interned_events_capacity == capacity);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == threads_count);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == cme_iseq_count);
  if (strcmp(allocation, "unique_stacks_array") == 0) {
    assert(stack_dedup_state.unique_stacks_array == array);
    assert(stack_dedup_state.unique_stacks_pos == pos);
    assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == stacks_count);
  } else {
    assert(stack_dedup_state.unique_stacks_pos == 0);
    assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  }
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  assert_allocation_accounting();

  thrd_t thread;
  assert(thrd_create(&thread, check_consumer_mutex_unlocked, NULL) == thrd_success);
  int result_code;
  assert(thrd_join(thread, &result_code) == thrd_success);
  assert(result_code == 0);

  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_OK);
  assert(consumer_state.interned_events_count == 1);
  miteruby_stack_t stack = miteruby_stack_dedup_get(queue[0].stack_id);
  assert(stack.frame_count == 1);
  miteruby_event_frame_position_t position;
  miteruby_event_frame_refs_t refs = miteruby_hack_id_to_frame_refs(miteruby_hack_location_id_to_cme_seq_id(stack.ids[0], &position));
  assert(refs.cme == storage.event.refs[0].cme && refs.iseq == storage.event.refs[0].iseq);
  assert(position.value == positions_for(&storage.event)[0].value);

  miteruby_consumer_reset();
  assert(consumer_state.interned_events_count == 0);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 0);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == 0);
  assert_allocation_accounting();
}

static miteruby_stack_dedup_id_t assert_dedup(const miteruby_event_stack_sample_t *event, bool inserted) {
  miteruby_stack_hash_t stack_hash = miteruby_stack_hash(event);
  size_t pos = stack_dedup_state.unique_stacks_pos;
  size_t count = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks);
  miteruby_stack_dedup_result_t result = miteruby_stack_dedup_get_or_reserve(event->header.frame_count, stack_hash);
  assert(!result.error_storage_full);
  assert(result.ok.reserved == inserted);
  assert(stack_dedup_state.unique_stacks_pos == pos);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == count);
  if (inserted) {
    assert(result.ok.stack.ids != NULL);
    const miteruby_event_frame_position_t *positions = (const miteruby_event_frame_position_t *)&event->refs[event->header.frame_count];
    for (uint16_t i = 0; i < event->header.frame_count; i++) result.ok.stack.ids[i].value.value = positions[i].value + i;
    assert(miteruby_stack_dedup_commit(result.ok.id, stack_hash));
  } else {
    assert(result.ok.stack.ids == NULL);
  }
  verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_get(
    &stack_dedup_state.unique_stacks, stack_hash
  );
  assert(!verstable_unique_stacks_map_is_end(entry));
  assert(entry.data->val.offset == result.ok.id.offset);
  return result.ok.id;
}

static void test_empty_stack_before_nonempty(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  assert(assert_dedup(&(miteruby_event_stack_sample_t) {0}, true).offset == 0);
  assert(assert_dedup(&(miteruby_event_stack_sample_t) {0}, false).offset == 0);
  assert(stack_dedup_state.unique_stacks_pos == 8);
  assert(miteruby_stack_dedup_get((miteruby_stack_dedup_id_t) {.offset = 0}).frame_count == 0);

  event->header.frame_count = 1;
  positions_for(event)[0].value = 7;
  assert(assert_dedup(event, true).offset == 8);
  assert(stack_dedup_state.unique_stacks_pos == 16);
  miteruby_stack_t stored = miteruby_stack_dedup_get((miteruby_stack_dedup_id_t) {.offset = 8});
  assert(stored.frame_count == 1);
  assert(stored.ids[0].value.value == 7);
  assert(assert_dedup(&(miteruby_event_stack_sample_t) {0}, false).offset == 0);
  assert(miteruby_stack_dedup_get((miteruby_stack_dedup_id_t) {.offset = 0}).frame_count == 0);
  assert(assert_dedup(event, false).offset == 8);
  assert(stack_dedup_state.unique_stacks_pos == 16);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 2);
  assert(miteruby_stack_dedup_reset());
}

static void test_stack_identity(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 2;
  event->header.size_bytes = 72;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->refs[0].iseq = (const rb_iseq_t *)&storage.words[15];
  positions_for(event)[0].value = 12;
  positions_for(event)[1].value = UINT16_MAX;

  miteruby_stack_dedup_id_t first = assert_dedup(event, true);
  assert(first.offset == 0);
  size_t used = stack_dedup_state.unique_stacks_pos;
  assert(used == 16);
  size_t data_size = 2 * (sizeof(miteruby_event_frame_refs_t) + sizeof(miteruby_event_frame_position_t));
  assert(miteruby_stack_dedup_get(first).ids[0].value.value == 12 && miteruby_stack_dedup_get(first).ids[1].value.value == UINT16_MAX + 1U);
  sample_storage duplicate = storage;
  duplicate.event.header.timestamp.ns = 123;
  duplicate.event.header.cpu_time.ns = 456;
  duplicate.event.header.flags = MITERUBY_EVENT_STACK_TRUNCATED | MITERUBY_EVENT_FROM_SIGNAL_HANDLER;
  duplicate.event.thread.value = Qtrue;
  memset((char *)duplicate.event.refs + data_size, 0xff, 4);
  assert(assert_dedup(&duplicate.event, false).offset == first.offset);
  assert(stack_dedup_state.unique_stacks_pos == used);

  miteruby_event_frame_refs_t first_refs = duplicate.event.refs[0];
  duplicate.event.refs[0] = duplicate.event.refs[1];
  duplicate.event.refs[1] = first_refs;
  positions_for(&duplicate.event)[0].value = UINT16_MAX;
  positions_for(&duplicate.event)[1].value = 12;
  assert(assert_dedup(&duplicate.event, true).offset != first.offset);

  positions_for(event)[0].value++;
  miteruby_stack_dedup_id_t other_position = assert_dedup(event, true);
  assert(other_position.offset != first.offset);
  event->refs[0].cme = NULL;
  miteruby_stack_dedup_id_t other_cme = assert_dedup(event, true);
  assert(other_cme.offset != other_position.offset);
  event->refs[0].iseq = NULL;
  assert(assert_dedup(event, true).offset != other_cme.offset);
  event->header.frame_count = 1;
  assert(assert_dedup(event, true).offset != first.offset);

  event->header.frame_count = 0;
  used = stack_dedup_state.unique_stacks_pos;
  miteruby_stack_dedup_id_t empty = assert_dedup(event, true);
  assert(empty.offset == used);
  assert(assert_dedup(event, false).offset == empty.offset);
  assert(stack_dedup_state.unique_stacks_pos == used + 8);
  assert(miteruby_stack_dedup_get(empty).frame_count == 0);
  assert(miteruby_stack_dedup_get(first).frame_count == 2);
}

static void test_hash_collision_reuses_first_stack(void) {
  assert(miteruby_stack_dedup_reset());
  sample_storage storage = {0};
  storage.event.header.frame_count = 1;
  positions_for(&storage.event)[0].value = 12;
  miteruby_stack_hash_t stack_hash = miteruby_stack_hash(&storage.event);
  miteruby_stack_dedup_id_t first = assert_dedup(&storage.event, true);
  size_t used = stack_dedup_state.unique_stacks_pos;

  positions_for(&storage.event)[0].value = 13;
  // Supply the first stack's hash to simulate a collision with different stack contents.
  miteruby_stack_dedup_result_t result = miteruby_stack_dedup_get_or_reserve(storage.event.header.frame_count, stack_hash);
  assert(!result.error_storage_full);
  assert(!result.ok.reserved);
  assert(result.ok.id.offset == first.offset);
  assert(stack_dedup_state.unique_stacks_pos == used);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(miteruby_stack_dedup_get(first).ids[0].value.value == 12);
  assert(miteruby_stack_dedup_reset());
}

static void test_fills_reserved_stack(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 2;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->refs[1].iseq = (const rb_iseq_t *)&storage.words[15];
  positions_for(event)[0].value = 19;
  positions_for(event)[1].value = 27;
  miteruby_stack_dedup_id_t stack_id = assert_dedup(event, true);
  miteruby_stack_t stored = miteruby_stack_dedup_get(stack_id);
  assert(stored.frame_count == 2);
  assert(stored.ids[0].value.value == 19 && stored.ids[1].value.value == 28);

  positions_for(event)[0].value++;
  event->refs[0].cme = NULL;
  assert(stored.ids[0].value.value == 19);
  assert(assert_dedup(event, true).offset != stack_id.offset);
  positions_for(event)[0].value--;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  assert(assert_dedup(event, false).offset == stack_id.offset);
}

static void test_map_growth_and_stable_storage(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 3;
  uint8_t *array = stack_dedup_state.unique_stacks_array;
  miteruby_stack_dedup_id_t ids[20000];
  for (uint16_t i = 0; i < 20000; i++) {
    positions_for(event)[0].value = i;
    ids[i] = assert_dedup(event, true);
    assert(ids[i].offset % 8 == 0);
  }
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) == UNIQUE_STACKS_ARRAY_MAX_SIZE);
  assert(stack_dedup_state.unique_stacks_array == array);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets) > 0);
  assert_allocation_accounting();

  size_t used = stack_dedup_state.unique_stacks_pos;
  for (uint16_t i = 0; i < 20000; i++) {
    positions_for(event)[0].value = i;
    assert(assert_dedup(event, false).offset == ids[i].offset);
    miteruby_stack_t stored = miteruby_stack_dedup_get(ids[i]);
    assert(stored.frame_count == 3);
    assert(stored.ids[0].value.value == i && stored.ids[1].value.value == 1 && stored.ids[2].value.value == 2);
  }
  assert(stack_dedup_state.unique_stacks_pos == used);
  miteruby_stack_dedup_id_t empty = assert_dedup(&(miteruby_event_stack_sample_t) {0}, false);
  assert(miteruby_stack_dedup_get(empty).frame_count == 0);
  for (
    verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_first(&stack_dedup_state.unique_stacks);
    !verstable_unique_stacks_map_is_end(entry);
    entry = verstable_unique_stacks_map_next(entry)
  ) {
    assert(entry.data->val.offset < used);
  }
}

static void assert_failed_dedup(const miteruby_event_stack_sample_t *event) {
  size_t count = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks);
  size_t pos = stack_dedup_state.unique_stacks_pos;
  uint8_t *array = stack_dedup_state.unique_stacks_array;
  miteruby_stack_hash_t stack_hash = miteruby_stack_hash(event);
  miteruby_stack_dedup_result_t result = miteruby_stack_dedup_get_or_reserve(event->header.frame_count, stack_hash);
  if (!result.error_storage_full) {
    assert(result.ok.reserved);
    memset(result.ok.stack.ids, 0, event->header.frame_count * sizeof(*result.ok.stack.ids));
    assert(!miteruby_stack_dedup_commit(result.ok.id, stack_hash));
  }
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == count);
  assert(stack_dedup_state.unique_stacks_pos == pos);
  assert(stack_dedup_state.unique_stacks_array == array);
  for (
    verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_first(&stack_dedup_state.unique_stacks);
    !verstable_unique_stacks_map_is_end(entry);
    entry = verstable_unique_stacks_map_next(entry)
  ) {
    assert(entry.data->val.offset < pos);
  }
}

static void test_dedup_errors(void) {
  assert(miteruby_stack_dedup_reset());
  verstable_unique_stacks_map_cleanup(&stack_dedup_state.unique_stacks);
  verstable_unique_stacks_map_init(&stack_dedup_state.unique_stacks);
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 1;

  failed_allocation_name = "unique_stacks_map";
  assert_failed_dedup(event);
  failed_allocation_name = NULL;
  assert(assert_dedup(event, true).offset == 0);
  for (uint16_t i = 1; i < 7; i++) {
    positions_for(event)[0].value = i;
    assert_dedup(event, true);
  }
  positions_for(event)[0].value = 7;
  failed_allocation_name = "unique_stacks_map";
  assert_failed_dedup(event);
  event->header.type = MITERUBY_EVENT_STACK_SAMPLE;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  size_t events_count = consumer_state.interned_events_count;
  size_t stacks_pos = stack_dedup_state.unique_stacks_pos;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_DEDUP_STORAGE_FULL);
  assert(consumer_state.interned_events_count == events_count);
  assert(stack_dedup_state.unique_stacks_pos == stacks_pos);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 7);
  miteruby_cme_iseq_id_t retained_id = verstable_mark_cme_iseq_map_get(&consumer_state.mark_cme_iseq_map, event->refs[0]).data->val;
  failed_allocation_name = NULL;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  miteruby_stack_dedup_id_t stack_id = consumer_state.interned_events_queue[events_count].stack_id;
  assert(stack_id.offset == stacks_pos);
  miteruby_stack_t stack = miteruby_stack_dedup_get(stack_id);
  miteruby_event_frame_position_t position;
  assert(miteruby_hack_location_id_to_cme_seq_id(stack.ids[0], &position).value.value == retained_id.value.value);
  assert(position.value == 7);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 8);
  failed_allocation_name = "unique_stacks_map";
  event->refs[0].cme = NULL;
  positions_for(event)[0].value = 0;
  assert(assert_dedup(event, false).offset == 0);
  failed_allocation_name = NULL;
  assert_allocation_accounting();
}

static void test_unique_stacks_map_capacity(void) {
  assert(miteruby_stack_dedup_reset());
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 1;
  size_t count = 0;
  size_t upper_bound = UNIQUE_STACKS_MAP_MAX_SIZE / sizeof(*stack_dedup_state.unique_stacks.buckets);
  while (count < upper_bound) {
    event->refs[0].iseq = (const rb_iseq_t *)(uintptr_t)(count + 1);
    miteruby_stack_hash_t stack_hash = miteruby_stack_hash(event);
    miteruby_stack_dedup_result_t result = miteruby_stack_dedup_get_or_reserve(event->header.frame_count, stack_hash);
    assert(!result.error_storage_full && result.ok.reserved);
    result.ok.stack.ids[0].value.value = 0;
    if (!miteruby_stack_dedup_commit(result.ok.id, stack_hash)) break;
    count++;
  }
  assert(count > 20000 && count < upper_bound);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == count);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets) <= UNIQUE_STACKS_MAP_MAX_SIZE);
  assert(stack_dedup_state.unique_stacks_pos + 8 <= UNIQUE_STACKS_ARRAY_MAX_SIZE);
  assert_failed_dedup(event);
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  event->refs[0].iseq = (const rb_iseq_t *)(uintptr_t)1;
  assert(assert_dedup(event, false).offset == 0);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  assert_allocation_accounting();
}

static void test_fixed_array_capacity(void) {
  miteruby_consumer_reset();
  uint8_t *array = stack_dedup_state.unique_stacks_array;
  union {
    miteruby_event_stack_sample_t event;
    uint64_t words[MITERUBY_MAX_SIZE_BYTES / sizeof(uint64_t)];
  } full_storage = {0};
  miteruby_event_stack_sample_t *event = &full_storage.event;
  event->header.frame_count = MITERUBY_MAX_FRAMES;
  miteruby_event_frame_position_t *positions = positions_for(event);
  assert(assert_dedup(event, true).offset == 0);
  size_t compact_stack_size = 1608;
  uint16_t position = 1;
  while (UNIQUE_STACKS_ARRAY_MAX_SIZE - stack_dedup_state.unique_stacks_pos >= compact_stack_size) {
    positions[0].value = position++;
    assert_dedup(event, true);
  }

  positions[0].value = position;
  assert_failed_dedup(event);
  size_t remaining = UNIQUE_STACKS_ARRAY_MAX_SIZE - stack_dedup_state.unique_stacks_pos;
  assert(remaining < compact_stack_size);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) == 16U * 1024U * 1024U);
  assert(stack_dedup_state.unique_stacks_array == array);
  if (remaining > 0) {
    miteruby_stack_dedup_result_t last = miteruby_stack_dedup_get_or_reserve(
      (uint16_t) ((remaining - 4) / 4), (miteruby_stack_hash_t) {.hash = UINT64_MAX}
    );
    assert(!last.error_storage_full && last.ok.reserved);
    memset(last.ok.stack.ids, 0, last.ok.stack.frame_count * sizeof(*last.ok.stack.ids));
    assert(miteruby_stack_dedup_commit(last.ok.id, (miteruby_stack_hash_t) {.hash = UINT64_MAX}));
  }
  assert(stack_dedup_state.unique_stacks_pos == UNIQUE_STACKS_ARRAY_MAX_SIZE);
  assert_failed_dedup(&(miteruby_event_stack_sample_t) {0});
  positions[0].value = 0;
  assert(assert_dedup(event, false).offset == 0);

  sample_storage storage = {0};
  storage.event.header.type = MITERUBY_EVENT_STACK_SAMPLE;
  storage.event.thread.value = Qtrue;
  size_t previous_events_count = consumer_state.interned_events_count;
  size_t previous_cme_iseq_count = verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map);
  size_t previous_threads_count = verstable_mark_threads_set_size(&consumer_state.mark_threads_set);
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_DEDUP_STORAGE_FULL);
  assert(consumer_state.interned_events_count == previous_events_count);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == previous_threads_count);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == previous_cme_iseq_count);
  assert_allocation_accounting();

  assert(miteruby_stack_dedup_reset());
  assert(assert_dedup(event, true).offset == 0);
  assert_allocation_accounting();
}

static void test_compact_events_and_reset(void) {
  miteruby_consumer_reset();
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
  event->refs[1] = event->refs[0];
  miteruby_event_deduped_sample_t *queue = consumer_state.interned_events_queue;
  size_t capacity = consumer_state.interned_events_capacity;
  assert(capacity == (16U * 1024U * 1024U) / sizeof(*queue));
  for (size_t i = 0; i < capacity; i++) {
    event->header.timestamp.ns = 123 + i;
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  }
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 1);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == 1);
  assert(consumer_state.interned_events_count == capacity);
  assert(consumer_state.interned_events_capacity == capacity);
  assert(consumer_state.interned_events_queue == queue);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets) > 0);
  assert_allocation_accounting();
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  size_t stacks_pos = stack_dedup_state.unique_stacks_pos;
  event->thread.value = Qtrue;
  positions_for(event)[0].value++;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_INTERNED_EVENTS_QUEUE_FULL);
  assert(consumer_state.interned_events_count == capacity);
  assert(consumer_state.interned_events_capacity == capacity);
  assert(consumer_state.interned_events_queue == queue);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(stack_dedup_state.unique_stacks_pos == stacks_pos);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 1);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == 1);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  positions_for(event)[0].value--;

  for (size_t i = 0; i < capacity; i++) {
    const miteruby_event_deduped_sample_t *deduped = &consumer_state.interned_events_queue[i];
    assert(deduped->header.type == MITERUBY_EVENT_DEDUPED_SAMPLE);
    assert(deduped->header.size_bytes == sizeof(*deduped));
    assert(deduped->header.frame_count == 2);
    assert(deduped->header.flags == event->header.flags);
    assert(deduped->header.timestamp.ns == (long)(123 + i));
    assert(deduped->header.cpu_time.ns == 456);
    assert(deduped->thread.value == Qnil && deduped->stack_id.offset == 0);
  }

  miteruby_event_overflow_t overflow = {.header = {.type = MITERUBY_EVENT_OVERFLOW, .size_bytes = sizeof(overflow)}};
  size_t previous_count = consumer_state.interned_events_count;
  assert(buffer_event(&overflow.header) == MITERUBY_CONSUMER_OK);
  assert(consumer_state.interned_events_count == previous_count);
  overflow.header.type = MITERUBY_EVENT_INVALID;
  assert(buffer_event(&overflow.header) == MITERUBY_CONSUMER_OK);
  assert(consumer_state.interned_events_count == previous_count);

  consumer_state.interned_events_count = 0;
  event->thread.value = Qtrue;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 2);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == 1);

  miteruby_consumer_reset();
  assert_allocation_accounting();
  assert(consumer_state.interned_events_count == 0 && stack_dedup_state.unique_stacks_pos == 0);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) == UNIQUE_STACKS_ARRAY_MAX_SIZE && stack_dedup_state.unique_stacks_array != NULL);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 0);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == 0);
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(consumer_state.interned_events_queue[0].stack_id.offset == 0);
}

static void assert_allocator_limit(void *(*allocate)(size_t), void (*release)(void *, size_t), size_t limit) {
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  void *allocation = allocate(limit);
  assert(allocation != NULL);
  release(allocation, limit);
  assert(allocate(limit + 1) == NULL);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
}

static void assert_cme_iseq_id(miteruby_event_frame_refs_t refs, uint32_t expected_id) {
  verstable_mark_cme_iseq_map_itr entry = verstable_mark_cme_iseq_map_get(&consumer_state.mark_cme_iseq_map, refs);
  assert(!verstable_mark_cme_iseq_map_is_end(entry));
  assert(entry.data->val.value.value == expected_id);
  miteruby_event_frame_refs_t resolved = miteruby_hack_id_to_frame_refs(entry.data->val);
  assert(resolved.cme == refs.cme && resolved.iseq == refs.iseq);
}

static void assert_location_id(miteruby_event_frame_refs_t refs, miteruby_event_frame_position_t position, uint32_t expected_id) {
  verstable_mark_cme_iseq_map_itr cme_iseq = verstable_mark_cme_iseq_map_get(&consumer_state.mark_cme_iseq_map, refs);
  assert(!verstable_mark_cme_iseq_map_is_end(cme_iseq));
  verstable_location_map_itr location = verstable_location_map_get(
    &consumer_state.location_map, (miteruby_location_key_t) {.cme_iseq_id = cme_iseq.data->val, .position = position}
  );
  assert(!verstable_location_map_is_end(location));
  assert(location.data->val.location_id.value.value == expected_id);
  assert(location.data->val.iseq == refs.iseq);
  miteruby_event_frame_position_t resolved_position;
  miteruby_cme_iseq_id_t resolved_id = miteruby_hack_location_id_to_cme_seq_id(location.data->val.location_id, &resolved_position);
  assert(resolved_id.value.value == cme_iseq.data->val.value.value);
  assert(resolved_position.value == position.value);
}

static void test_cme_iseq_pair_identity(void) {
  miteruby_consumer_reset();
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.type = MITERUBY_EVENT_STACK_SAMPLE;
  event->header.frame_count = 1;
  event->thread.value = Qnil;
  const rb_callable_method_entry_t *cme = (const rb_callable_method_entry_t *)&storage.words[12];
  const rb_iseq_t *iseq = (const rb_iseq_t *)&storage.words[13];
  miteruby_event_frame_refs_t pairs[] = {
    {.cme = cme, .iseq = iseq},
    {.cme = cme, .iseq = (const rb_iseq_t *)&storage.words[14]},
    {.cme = (const rb_callable_method_entry_t *)&storage.words[15], .iseq = iseq},
    {.cme = cme, .iseq = NULL},
    {.cme = NULL, .iseq = iseq},
  };
  size_t count = sizeof(pairs) / sizeof(*pairs);
  for (size_t i = 0; i < count; i++) {
    event->refs[0] = pairs[i];
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
    assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == i + 1);
    assert_cme_iseq_id(pairs[i], i);
    assert_location_id(pairs[i], positions_for(event)[0], i);
    miteruby_stack_t stack = miteruby_stack_dedup_get(consumer_state.interned_events_queue[i].stack_id);
    assert(stack.frame_count == 1 && stack.ids[0].value.value == i);
  }

  positions_for(event)[0].value++;
  for (size_t i = 0; i < count; i++) {
    event->refs[0] = pairs[i];
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
    assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == count);
    assert_location_id(pairs[i], positions_for(event)[0], count + i);
    miteruby_stack_t stack = miteruby_stack_dedup_get(consumer_state.interned_events_queue[count + i].stack_id);
    assert(stack.frame_count == 1 && stack.ids[0].value.value == count + i);
  }

  assert(verstable_location_map_size(&consumer_state.location_map) == count * 2);
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  event->header.frame_count = 2;
  event->refs[1] = event->refs[0];
  positions_for(event)[0].value = 1;
  positions_for(event)[1].value = 1;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_location_map_size(&consumer_state.location_map) == count * 2);
  assert_location_id(event->refs[0], positions_for(event)[0], count * 2 - 1);
  miteruby_stack_t repeated = miteruby_stack_dedup_get(consumer_state.interned_events_queue[consumer_state.interned_events_count - 1].stack_id);
  assert(repeated.frame_count == 2);
  assert(repeated.ids[0].value.value == count * 2 - 1 && repeated.ids[1].value.value == count * 2 - 1);
  event->header.frame_count = 1;

  event->refs[0] = (miteruby_event_frame_refs_t) {0};
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_INVALID_FRAME);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == count);
  for (size_t i = 0; i < count; i++) {
    assert_cme_iseq_id(pairs[i], i);
  }

  miteruby_consumer_reset();
  event->refs[0] = pairs[count - 1];
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert_cme_iseq_id(event->refs[0], 0);
  assert_location_id(event->refs[0], positions_for(event)[0], 0);
  assert(verstable_location_map_size(&consumer_state.location_map) == 1);
}

static void test_retention_failure(bool fail_threads, size_t retained_objects, uint16_t frame_count) {
  miteruby_consumer_reset();
  verstable_mark_threads_set_cleanup(&consumer_state.mark_threads_set);
  verstable_mark_cme_iseq_map_cleanup(&consumer_state.mark_cme_iseq_map);
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.type = MITERUBY_EVENT_STACK_SAMPLE;
  event->thread.value = Qnil;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  if (fail_threads) {
    for (size_t i = 0; i < retained_objects - 1; i++) assert(retain_thread(LONG2FIX(i)));
  } else {
    for (size_t i = 0; i < retained_objects; i++) {
      assert(retain_cme_iseq((miteruby_event_frame_refs_t) {.cme = (const rb_callable_method_entry_t *)LONG2FIX(i)}, &(miteruby_cme_iseq_id_t) {0}) == MITERUBY_CONSUMER_OK);
    }
  }
  size_t stacks_pos = stack_dedup_state.unique_stacks_pos;

  event->thread.value = LONG2FIX(100);
  event->header.frame_count = frame_count;
  event->refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->refs[0].iseq = (const rb_iseq_t *)&storage.words[15];
  if (frame_count > 1) event->refs[1].cme = event->refs[0].cme;
  failed_allocation_name = fail_threads ? "mark_threads" : "mark_cme_iseq";
  assert(buffer_event(&event->header) ==
    (fail_threads ? MITERUBY_CONSUMER_MARK_THREADS_FULL : MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL));
  failed_allocation_name = NULL;

  assert(consumer_state.interned_events_count == 1);
  assert(consumer_state.interned_events_queue[0].thread.value == Qnil);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(stack_dedup_state.unique_stacks_pos == stacks_pos);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == (fail_threads ? 7U : 2U));
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == (fail_threads ? 0U : 7U));
  assert(assert_dedup(&(miteruby_event_stack_sample_t) {0}, false).offset == 0);
  thrd_t thread;
  assert(thrd_create(&thread, check_consumer_mutex_unlocked, NULL) == thrd_success);
  int result;
  assert(thrd_join(thread, &result) == thrd_success && result == 0);

  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(consumer_state.interned_events_count == 2);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == (frame_count ? 2U : 1U));
  assert(!verstable_mark_threads_set_is_end(verstable_mark_threads_set_get(&consumer_state.mark_threads_set, event->thread.value)));
  for (uint16_t i = 0; i < frame_count; i++) {
    assert_cme_iseq_id(event->refs[i], (fail_threads ? 0 : retained_objects) + i);
    miteruby_stack_t stack = miteruby_stack_dedup_get(consumer_state.interned_events_queue[1].stack_id);
    assert(stack.ids[i].value.value == i);
    miteruby_event_frame_position_t position;
    assert(miteruby_hack_location_id_to_cme_seq_id(stack.ids[i], &position).value.value == (fail_threads ? 0 : retained_objects) + i);
    assert(position.value == positions_for(event)[i].value);
  }
  assert_allocation_accounting();
}

static void test_mark_threads_capacity(void) {
  size_t initial_size = miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets);
  size_t count = 0;
  size_t upper_bound = MARK_THREADS_MAX_SIZE / sizeof(VALUE);
  while (count < upper_bound && retain_thread((VALUE)count)) count++;
  assert(count > 1000 && count < upper_bound);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets) > initial_size);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets) <= MARK_THREADS_MAX_SIZE);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == count);
  assert_allocation_accounting();
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  for (size_t i = 0; i < count; i++) assert(retain_thread((VALUE)i));
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
}

static void test_mark_cme_iseq_capacity(void) {
  size_t initial_size = miteruby_allocator_alloc_size(consumer_state.mark_cme_iseq_map.buckets);
  size_t count = 0;
  size_t upper_bound = (size_t) UINT20_MAX + 2;
  while (count < upper_bound && retain_cme_iseq((miteruby_event_frame_refs_t) {.cme = (const rb_callable_method_entry_t *)(count + 1)}, &(miteruby_cme_iseq_id_t) {0}) == MITERUBY_CONSUMER_OK) count++;
  assert(count > (size_t) UINT16_MAX + 1 && count < upper_bound);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_cme_iseq_map.buckets) > initial_size);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_cme_iseq_map.buckets) <= MARK_CME_ISEQ_MAX_SIZE);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == count);
  assert_allocation_accounting();
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  for (size_t i = 0; i < count; i++) {
    miteruby_event_frame_refs_t refs = {.cme = (const rb_callable_method_entry_t *)(i + 1)};
    miteruby_cme_iseq_id_t id;
    assert(retain_cme_iseq(refs, &id) == MITERUBY_CONSUMER_OK);
    assert(id.value.value == i);
    if (i == 0 || i == UINT16_MAX + 1U || i == count - 1) assert_cme_iseq_id(refs, i);
  }
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);

  sample_storage storage = {0};
  storage.event.header.type = MITERUBY_EVENT_STACK_SAMPLE;
  storage.event.header.frame_count = 1;
  storage.event.thread.value = Qnil;
  storage.event.refs[0].cme = (const rb_callable_method_entry_t *)(count + 1);
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_MARK_CME_ISEQ_FULL);
  assert(consumer_state.interned_events_count == 0);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(stack_dedup_state.unique_stacks_pos == 0);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == count);

  storage.event.refs[0].cme = (const rb_callable_method_entry_t *)count;
  positions_for(&storage.event)[0].value = UINT16_MAX;
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_OK);
  miteruby_stack_t stored = miteruby_stack_dedup_get(consumer_state.interned_events_queue[0].stack_id);
  assert(stored.frame_count == 1 && stored.ids[0].value.value == 0);
  miteruby_event_frame_position_t position;
  assert(miteruby_hack_location_id_to_cme_seq_id(stored.ids[0], &position).value.value == count - 1);
  assert(position.value == UINT16_MAX);
}

static size_t fill_thread_contexts(void) {
  size_t count = 0;
  for (; count < THREAD_CONTEXTS_MAX_CAPACITY / sizeof(consumer_thread_context); count++) {
    if (thread_context_for(LONG2FIX(count), (monotonic_time_t) {.ns = 10}, (cpu_time_t) {.ns = 20}) == NULL) break;
  }
  return count;
}

static void test_thread_contexts_capacity(void) {
  miteruby_consumer_recorder_init();
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  failed_allocation_name = "thread_contexts";
  assert(fill_thread_contexts() == 0);
  failed_allocation_name = NULL;
  assert(verstable_thread_contexts_map_size(&thread_contexts) == 0);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);

  size_t count = fill_thread_contexts();
  assert(verstable_thread_contexts_map_size(&thread_contexts) == count);
  assert(count > 20000 && count < THREAD_CONTEXTS_MAX_CAPACITY / sizeof(consumer_thread_context));
  assert(miteruby_allocator_requested_bytes() - allocated_bytes <= THREAD_CONTEXTS_MAX_CAPACITY);
  consumer_thread_context *context = thread_context_for(LONG2FIX(0), (monotonic_time_t) {.ns = 30}, (cpu_time_t) {.ns = 50});
  assert(context != NULL);
  miteruby_sample_values values = sample_values_for(context, (monotonic_time_t) {.ns = 30}, (cpu_time_t) {.ns = 50});
  assert(values.wall_time_ns == 20 && values.cpu_time_ns == 30);
  assert(verstable_thread_contexts_map_size(&thread_contexts) == count);
  miteruby_consumer_recorder_init();
  assert(verstable_thread_contexts_map_size(&thread_contexts) == 0);
  assert(thread_context_for(Qnil, (monotonic_time_t) {.ns = 10}, (cpu_time_t) {.ns = 20}) != NULL);
  assert(verstable_thread_contexts_map_size(&thread_contexts) == 1);
  verstable_thread_contexts_map_cleanup(&thread_contexts);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
}

static miteruby_raw_events_queue_t invalid_raw_events_queue;

static VALUE consume_invalid_raw_events_queue(DDTRACE_UNUSED VALUE unused) {
  miteruby_consumer_consume_loop(&invalid_raw_events_queue);
  return Qnil;
}

static void test_raw_events_queue_internal_error(void) {
  assert(miteruby_raw_events_queue_init(&invalid_raw_events_queue) == 0);
  invalid_raw_events_queue.data[0] = 2;
  atomic_store(&invalid_raw_events_queue.write_state, 1);
  sigset_t original_mask, current_mask;
  sigemptyset(&sigprof_signal_mask);
  sigaddset(&sigprof_signal_mask, SIGPROF);
  assert(pthread_sigmask(SIG_UNBLOCK, &sigprof_signal_mask, &original_mask) == 0);
  assert_runtime_error(consume_invalid_raw_events_queue, "Miteruby raw events queue internal error");
  assert(pthread_sigmask(SIG_BLOCK, NULL, &current_mask) == 0);
  assert(sigismember(&current_mask, SIGPROF) == 0);
  assert(pthread_sigmask(SIG_SETMASK, &original_mask, NULL) == 0);
  miteruby_raw_events_queue_destroy(&invalid_raw_events_queue);
}

static VALUE lookup_missing_frame(DDTRACE_UNUSED VALUE unused) {
  miteruby_hack_id_to_frame_refs((miteruby_cme_iseq_id_t) {.value = {.value = 0}});
  return Qnil;
}

static VALUE lookup_missing_location(DDTRACE_UNUSED VALUE unused) {
  miteruby_event_frame_position_t position;
  miteruby_hack_location_id_to_cme_seq_id((miteruby_location_id_t) {0}, &position);
  return Qnil;
}

static void test_invalid_frame(void) {
  miteruby_consumer_reset();
  assert_runtime_error(lookup_missing_frame, "Miteruby unknown CME/ISEQ ID: 0");
  assert_runtime_error(lookup_missing_location, "Miteruby unknown location ID: 0");
  sample_storage storage = {0};
  storage.event.header = (miteruby_event_header_t) {
    .type = MITERUBY_EVENT_STACK_SAMPLE, .size_bytes = 72, .frame_count = 2,
  };
  storage.event.thread.value = Qnil;
  storage.event.refs[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_INVALID_FRAME);
  assert(stack_dedup_state.unique_stacks_pos == 0);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(verstable_mark_cme_iseq_map_size(&consumer_state.mark_cme_iseq_map) == 1);
  assert_cme_iseq_id(storage.event.refs[0], 0);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 1);
  assert(consumer_state.interned_events_count == 0);

  storage.event.refs[1].cme = (const rb_callable_method_entry_t *)&storage.words[15];
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_OK);
  assert(consumer_state.interned_events_queue[0].stack_id.offset == 0);
  assert_cme_iseq_id(storage.event.refs[0], 0);
  assert_cme_iseq_id(storage.event.refs[1], 1);
  storage.event.refs[1].cme = NULL;
  miteruby_consumer_reset();

  assert(miteruby_raw_events_queue_init(&invalid_raw_events_queue) == 0);
  assert(miteruby_raw_events_queue_try_write(&invalid_raw_events_queue, storage.words, 9, NULL));
  assert_runtime_error(consume_invalid_raw_events_queue, "Miteruby invalid frame: both CME and ISEQ are NULL");
  assert(consumer_state.interned_events_count == 0);
  assert(stack_dedup_state.unique_stacks_pos == 0);
  miteruby_raw_events_queue_destroy(&invalid_raw_events_queue);
  miteruby_consumer_reset();
}

static void test_location_map(void) {
  miteruby_consumer_reset();
  verstable_location_map *map = &consumer_state.location_map;
  assert(verstable_location_map_size(map) == 0);
  miteruby_location_key_t key = {.cme_iseq_id = {.value = {.value = UINT20_MAX}}, .position = {.value = UINT16_MAX}};
  sample_storage storage = {0};
  miteruby_location_value_t value = {
    .location_id = {.value = {.value = UINT20_MAX}},
    .iseq = (const rb_iseq_t *)&storage,
  };
  verstable_location_map_itr entry = verstable_location_map_get_or_insert(map, key, value);
  assert(!verstable_location_map_is_end(entry));
  assert(entry.data->val.location_id.value.value == UINT20_MAX);
  assert(entry.data->val.iseq == value.iseq);

  miteruby_event_frame_position_t position;
  assert(miteruby_hack_location_id_to_cme_seq_id(value.location_id, &position).value.value == UINT20_MAX);
  assert(position.value == UINT16_MAX);

  miteruby_location_key_t same_key;
  memset(&same_key, 0xff, sizeof(same_key));
  same_key.cme_iseq_id.value.value = key.cme_iseq_id.value.value;
  same_key.position.value = key.position.value;
  entry = verstable_location_map_get_or_insert(map, same_key, (miteruby_location_value_t) {0});
  assert(!verstable_location_map_is_end(entry));
  assert(entry.data->val.location_id.value.value == UINT20_MAX);
  assert(entry.data->val.iseq == value.iseq);
  assert(verstable_location_map_size(map) == 1);

  key.position.value--;
  assert(verstable_location_map_is_end(verstable_location_map_get(map, key)));
  key.position.value++;
  key.cme_iseq_id.value.value--;
  assert(verstable_location_map_is_end(verstable_location_map_get(map, key)));
  assert_allocation_accounting();

  miteruby_consumer_reset();
  assert(verstable_location_map_size(map) == 0);
  assert_allocation_accounting();
}

static void test_location_interning_failure(void) {
  miteruby_consumer_reset();
  verstable_location_map_cleanup(&consumer_state.location_map);
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.type = MITERUBY_EVENT_STACK_SAMPLE;
  event->header.frame_count = 1;
  event->thread.value = Qnil;
  event->refs[0].iseq = (const rb_iseq_t *)&storage.words[15];
  failed_allocation_name = "location_map";
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_LOCATION_MAP_FULL);
  assert(consumer_state.interned_events_count == 0);
  assert(stack_dedup_state.unique_stacks_pos == 0);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert_cme_iseq_id(event->refs[0], 0);
  assert(verstable_location_map_size(&consumer_state.location_map) == 0);
  failed_allocation_name = NULL;

  for (uint16_t i = 0; i < 6; i++) {
    positions_for(event)[0].value = i;
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
    assert_location_id(event->refs[0], positions_for(event)[0], i);
  }
  size_t stacks_pos = stack_dedup_state.unique_stacks_pos;
  event->header.frame_count = 2;
  event->refs[1] = event->refs[0];
  positions_for(event)[0].value = 6;
  positions_for(event)[1].value = 7;
  failed_allocation_name = "location_map";
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_LOCATION_MAP_FULL);
  assert(consumer_state.interned_events_count == 6);
  assert(stack_dedup_state.unique_stacks_pos == stacks_pos);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 6);
  assert(verstable_location_map_size(&consumer_state.location_map) == 7);
  assert_location_id(event->refs[0], positions_for(event)[0], 6);

  positions_for(event)[1].value = 6;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_location_map_size(&consumer_state.location_map) == 7);
  failed_allocation_name = NULL;
  positions_for(event)[1].value = 7;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert_location_id(event->refs[1], positions_for(event)[1], 7);
  assert_allocation_accounting();
  miteruby_consumer_reset();
}

static void test_location_map_capacity(void) {
  miteruby_consumer_reset();
  size_t count = 0;
  for (; count <= UINT20_MAX; count++) {
    miteruby_location_key_t key = {.cme_iseq_id = {.value = {.value = (unsigned int) count}}};
    miteruby_location_id_t id = {.value = {.value = UINT20_MAX}};
    if (intern_location(key, NULL, &id) != MITERUBY_CONSUMER_OK) {
      assert(id.value.value == UINT20_MAX);
      break;
    }
    assert(id.value.value == count);
    verstable_location_map_itr entry = verstable_location_map_get(&consumer_state.location_map, key);
    assert(!verstable_location_map_is_end(entry));
    assert(entry.data->val.location_id.value.value == count);
  }
  assert(count > UINT16_MAX && count <= UINT20_MAX);
  assert(verstable_location_map_size(&consumer_state.location_map) == count);
  assert(miteruby_allocator_alloc_size(consumer_state.location_map.buckets) <= LOCATION_MAP_MAX_SIZE);
  miteruby_location_id_t id = {.value = {.value = UINT20_MAX}};
  assert(intern_location((miteruby_location_key_t) {0}, NULL, &id) == MITERUBY_CONSUMER_OK);
  assert(id.value.value == 0);
  assert_allocation_accounting();
  miteruby_consumer_reset();
}

int main(int argc, char **argv) {
  ruby_sysinit(&argc, &argv);
  RUBY_INIT_STACK;
  ruby_init();
  test_raw_events_queue_internal_error();
  test_initialization_failure();
  assert(miteruby_stack_dedup_init());
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) == UNIQUE_STACKS_ARRAY_MAX_SIZE && stack_dedup_state.unique_stacks_array != NULL);
  assert_allocation_accounting();
  test_invalid_frame();
  test_hash_collision_reuses_first_stack();
  test_empty_stack_before_nonempty();
  test_stack_identity();
  test_fills_reserved_stack();
  test_map_growth_and_stable_storage();
  miteruby_consumer_reset();
  test_dedup_errors();
  test_unique_stacks_map_capacity();
  test_fixed_array_capacity();
  test_compact_events_and_reset();
  test_cme_iseq_pair_identity();
  test_location_map();
  test_location_interning_failure();
  test_location_map_capacity();
  test_reset_failure("interned_events_queue", "Failed to allocate miteruby.interned_events_queue");
  test_reset_failure("unique_stacks_array", "Failure during miteruby_stack_dedup_reset");
  assert_allocator_limit(mark_threads_calloc, miteruby_allocator_free_sized, MARK_THREADS_MAX_SIZE);
  assert_allocator_limit(mark_cme_iseq_calloc, miteruby_allocator_free_sized, MARK_CME_ISEQ_MAX_SIZE);
  assert_allocator_limit(location_calloc, miteruby_allocator_free_sized, LOCATION_MAP_MAX_SIZE);
  assert_allocator_limit(unique_stacks_calloc, miteruby_allocator_free_sized, UNIQUE_STACKS_MAP_MAX_SIZE);
  assert_allocator_limit(thread_contexts_alloc, miteruby_allocator_free_sized, THREAD_CONTEXTS_MAX_CAPACITY);
  test_retention_failure(true, 7, 0);
  test_retention_failure(true, 7, 1);
  test_retention_failure(false, 7, 1);
  test_retention_failure(false, 6, 2);
  miteruby_consumer_reset();
  assert(consumer_state.interned_events_count == 0);
  assert(stack_dedup_state.unique_stacks_pos == 0);
  test_mark_threads_capacity();
  test_mark_cme_iseq_capacity();
  test_thread_contexts_capacity();
  verstable_unique_stacks_map_cleanup(&stack_dedup_state.unique_stacks);
  verstable_mark_threads_set_cleanup(&consumer_state.mark_threads_set);
  verstable_mark_cme_iseq_map_cleanup(&consumer_state.mark_cme_iseq_map);
  verstable_location_map_cleanup(&consumer_state.location_map);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets) == 0);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets) == 0);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_cme_iseq_map.buckets) == 0);
  miteruby_allocator_free(stack_dedup_state.unique_stacks_array);
  miteruby_allocator_free(consumer_state.interned_events_queue);
  assert(miteruby_allocator_requested_bytes() == 0);
  mtx_destroy(&consumer_state.mutex);
  puts("Miteruby consumer tests passed");
  return ruby_cleanup(0);
}
