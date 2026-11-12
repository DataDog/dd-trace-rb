#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"
#include <string.h>

static const char *failed_allocation_name;
static void assert_consumer_storage_full(void);
static void assert_frame_storage_full(void);

static void *test_allocator_alloc(size_t size, const char *name) {
  if (failed_allocation_name != NULL && strcmp(name, failed_allocation_name) == 0) return NULL;
  return miteruby_allocator_alloc(size, name);
}

#define miteruby_allocator_alloc test_allocator_alloc
#include "../../../ext/datadog_profiling_native_extension/miteruby/stack_dedup.c"
static void test_mark_locations(const VALUE *start, const VALUE *end);
#define rb_gc_mark_locations test_mark_locations
#include "../../../ext/datadog_profiling_native_extension/miteruby/consumer.c"
#undef rb_gc_mark_locations
#undef miteruby_allocator_alloc

#undef NDEBUG
#include <assert.h>
#include <stdio.h>

static bool testing_consumer_mark;
static const VALUE *marked_start;
static const VALUE *marked_end;

static void test_mark_locations(const VALUE *start, const VALUE *end) {
  assert(testing_consumer_mark);
  marked_start = start;
  marked_end = end;
}

void miteruby_raw_events_queue_mark(miteruby_raw_events_queue_t *raw_events_queue) {
  assert(testing_consumer_mark && raw_events_queue == consumer_state.raw_events_queue);
}

typedef union {
  miteruby_event_stack_sample_t event;
  uint64_t words[16];
} sample_storage;

static miteruby_event_deduped_sample_t *event_at(size_t index) {
  size_t pos = 0;
  while (index-- > 0) {
    miteruby_event_deduped_sample_t *event = (miteruby_event_deduped_sample_t *)(consumer_state.interned_events_queue + pos);
    assert(event->header.size_bytes >= sizeof(*event));
    pos += event->header.size_bytes;
  }
  return (miteruby_event_deduped_sample_t *)(consumer_state.interned_events_queue + pos);
}

static size_t buffered_event_count(void) {
  size_t count = 0;
  for (size_t pos = 0; pos < consumer_state.interned_events_pos; count++) {
    miteruby_event_deduped_sample_t *event = (miteruby_event_deduped_sample_t *)(consumer_state.interned_events_queue + pos);
    assert(event->header.size_bytes >= sizeof(*event));
    pos += event->header.size_bytes;
  }
  return count;
}

static miteruby_stack_t get_stack(miteruby_stack_dedup_id_t id) {
  return miteruby_stack_dedup_get(consumer_state.interned_events_queue, id);
}

static miteruby_stack_dedup_result_t reserve_stack(uint16_t frame_count, miteruby_stack_hash_t hash) {
  return miteruby_stack_dedup_get_or_reserve(
    frame_count, hash, consumer_state.interned_events_queue, consumer_state.interned_events_pos, consumer_state.interned_events_capacity
  );
}

static bool commit_stack(miteruby_stack_dedup_id_t id, miteruby_stack_hash_t hash, const uint8_t *end) {
  if (!miteruby_stack_dedup_commit(consumer_state.interned_events_queue, id, hash, end)) return false;
  miteruby_event_deduped_sample_t *event = (miteruby_event_deduped_sample_t *)(consumer_state.interned_events_queue + id.offset);
  event->stack_id = id;
  consumer_state.interned_events_pos += event->header.size_bytes;
  return true;
}

static void reset_stacks(void) {
  miteruby_stack_dedup_reset();
  consumer_state.interned_events_pos = 0;
}

static miteruby_bytecode_pos_t *bytecode_positions_for(miteruby_event_stack_sample_t *event) {
  return (miteruby_bytecode_pos_t *)&event->frames[event->header.frame_count];
}

static miteruby_location_id_t stack_location_id(miteruby_stack_t stack, uint16_t index) {
  assert(index < stack.frame_count);
  const uint8_t *cursor = stack.ids;
  miteruby_location_id_t id = {0};
  for (uint16_t i = 0; i <= index; i++) {
    assert(miteruby_compressed_deltas_read(id.value, &id.value, &cursor, stack.end));
  }
  if (index + 1 == stack.frame_count) assert(cursor == stack.end);
  return id;
}

static const uint8_t *fill_max_size_ids(miteruby_stack_t stack) {
  uint8_t *cursor = stack.ids;
  uint20_t previous = {0};
  for (uint16_t i = 0; i < stack.frame_count; i++) {
    uint20_t current = {.value = i % 2 == 0 ? UINT20_MAX : 0};
    assert(miteruby_compressed_deltas_write(previous, current, &cursor, stack.end));
    previous = current;
  }
  assert(cursor == stack.end);
  return cursor;
}

static void assert_allocation_accounting(void) {
  assert(consumer_state.location_array.count == verstable_location_set_size(&consumer_state.location_set));
  assert(consumer_state.mark_frame_array.count == verstable_mark_frame_set_size(&consumer_state.mark_frame_set));
  assert(miteruby_allocator_requested_bytes() ==
    miteruby_allocator_alloc_size(consumer_state.raw_events_queue) +
    miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets) +
    miteruby_allocator_alloc_size(consumer_state.mark_frame_set.buckets) +
    miteruby_allocator_alloc_size(consumer_state.mark_frame_array.entries) +
    miteruby_allocator_alloc_size(consumer_state.location_set.buckets) +
    miteruby_allocator_alloc_size(consumer_state.location_array.entries) +
    miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets) +
    miteruby_allocator_alloc_size(consumer_state.interned_events_queue));
  assert(consumer_size(&consumer_state) == sizeof(consumer_state) +
    sizeof(stack_dedup_state.unique_stacks) + miteruby_allocator_requested_bytes());
}

static VALUE initialize_consumer(DDTRACE_UNUSED VALUE unused) {
  miteruby_consumer_init();
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

static int check_consumer_mutex_unlocked(DDTRACE_UNUSED void *unused) {
  assert(mtx_trylock(&consumer_state.mutex) == thrd_success);
  assert(mtx_unlock(&consumer_state.mutex) == thrd_success);
  return 0;
}

static void test_reset_failure(const char *allocation, const char *message) {
  miteruby_consumer_reset();
  sample_storage storage = {0};
  storage.event.header.frame_count = 1;
  storage.event.thread.value = Qnil;
  storage.event.frames[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  storage.event.frames[0].iseq = (const rb_iseq_t *)&storage.words[15];
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_OK);

  miteruby_location_t *locations = consumer_state.location_array.entries;
  uint8_t *queue = consumer_state.interned_events_queue;
  miteruby_mark_frame_array_t *array = &consumer_state.mark_frame_array;
  miteruby_frame_t *entries = array->entries;
  size_t events_count = buffered_event_count();
  size_t capacity = consumer_state.interned_events_capacity;
  size_t frame_count = verstable_mark_frame_set_size(&consumer_state.mark_frame_set);
  size_t threads_count = verstable_mark_threads_set_size(&consumer_state.mark_threads_set);
  size_t stacks_count = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks);
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  assert(events_count > 0 && stacks_count > 0 && threads_count > 0 && frame_count > 0);

  failed_allocation_name = allocation;
  assert_runtime_error(reset_consumer, message);
  failed_allocation_name = NULL;

  assert(consumer_state.location_array.entries == locations && consumer_state.location_array.count == 1);
  assert(consumer_state.location_array.capacity == LOCATION_ARRAY_CAPACITY);
  assert(consumer_state.location_set.ctx == &consumer_state.location_array);
  assert(consumer_state.interned_events_queue == queue);
  assert(array->entries == entries && array->count == 1);
  assert(array->capacity == MARK_FRAME_ARRAY_CAPACITY);
  assert(array->entries[0].cme == storage.event.frames[0].cme && array->entries[0].iseq == storage.event.frames[0].iseq);
  assert(buffered_event_count() == 0);
  assert(consumer_state.interned_events_capacity == capacity);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == threads_count);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == frame_count);
  assert(consumer_state.interned_events_pos == 0);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  assert_allocation_accounting();

  thrd_t thread;
  assert(thrd_create(&thread, check_consumer_mutex_unlocked, NULL) == thrd_success);
  int result_code;
  assert(thrd_join(thread, &result_code) == thrd_success);
  assert(result_code == 0);

  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_OK);
  assert(buffered_event_count() == 1);
  miteruby_stack_t stack = get_stack(event_at(0)->stack_id);
  assert(stack.frame_count == 1);
  miteruby_location_t location = consumer_state.location_array.entries[stack_location_id(stack, 0).value.value];
  miteruby_frame_t frame = consumer_state.mark_frame_array.entries[location.frame_id.value];
  assert(frame.cme == storage.event.frames[0].cme && frame.iseq == storage.event.frames[0].iseq);
  assert(location.bytecode_pos.value == bytecode_positions_for(&storage.event)[0].value);

  miteruby_consumer_reset();
  assert(buffered_event_count() == 0);
  assert(array->count == 0 && array->capacity == MARK_FRAME_ARRAY_CAPACITY);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 0);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == 0);
  assert_allocation_accounting();
}

static miteruby_stack_dedup_id_t assert_dedup(const miteruby_event_stack_sample_t *event, bool inserted) {
  miteruby_stack_hash_t stack_hash = miteruby_stack_hash(event);
  size_t pos = consumer_state.interned_events_pos;
  size_t count = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks);
  miteruby_stack_dedup_result_t result = reserve_stack(event->header.frame_count, stack_hash);
  assert(!result.error_storage_full);
  assert(result.ok.reserved == inserted);
  assert(consumer_state.interned_events_pos == pos);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == count);
  if (inserted) {
    assert(result.ok.stack.ids != NULL);
    const miteruby_bytecode_pos_t *bytecode_positions = (const miteruby_bytecode_pos_t *)&event->frames[event->header.frame_count];
    uint8_t *cursor = result.ok.stack.ids;
    uint20_t previous = {0};
    for (uint16_t i = 0; i < event->header.frame_count; i++) {
      uint20_t current = {.value = bytecode_positions[i].value + i};
      assert(miteruby_compressed_deltas_write(previous, current, &cursor, result.ok.stack.end));
      previous = current;
    }
    assert(commit_stack(result.ok.id, stack_hash, cursor));
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
  assert(consumer_state.interned_events_pos == 48);
  assert(get_stack((miteruby_stack_dedup_id_t) {.offset = 0}).frame_count == 0);

  event->header.frame_count = 1;
  bytecode_positions_for(event)[0].value = 7;
  assert(assert_dedup(event, true).offset == 48);
  assert(consumer_state.interned_events_pos == 96);
  miteruby_stack_t stored = get_stack((miteruby_stack_dedup_id_t) {.offset = 48});
  assert(stored.frame_count == 1);
  assert(stack_location_id(stored, 0).value.value == 7);
  assert(assert_dedup(&(miteruby_event_stack_sample_t) {0}, false).offset == 0);
  assert(get_stack((miteruby_stack_dedup_id_t) {.offset = 0}).frame_count == 0);
  assert(assert_dedup(event, false).offset == 48);
  assert(consumer_state.interned_events_pos == 96);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 2);
  event->header.frame_count = 2;
  bytecode_positions_for(event)[0].value = 9;
  bytecode_positions_for(event)[1].value = 8;
  assert(assert_dedup(event, true).offset == 96);
  stored = get_stack((miteruby_stack_dedup_id_t) {.offset = 96});
  assert(stack_location_id(stored, 0).value.value == 9 && stack_location_id(stored, 1).value.value == 9);
  assert(consumer_state.interned_events_pos == 144);
  reset_stacks();
}

static void test_stack_identity(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 2;
  event->header.size_bytes = 72;
  event->frames[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->frames[0].iseq = (const rb_iseq_t *)&storage.words[15];
  bytecode_positions_for(event)[0].value = 12;
  bytecode_positions_for(event)[1].value = UINT16_MAX;

  miteruby_stack_dedup_id_t first = assert_dedup(event, true);
  assert(first.offset == 0);
  size_t used = consumer_state.interned_events_pos;
  assert(used == 48);
  size_t data_size = 2 * (sizeof(miteruby_frame_t) + sizeof(miteruby_bytecode_pos_t));
  assert(stack_location_id(get_stack(first), 0).value.value == 12 && stack_location_id(get_stack(first), 1).value.value == UINT16_MAX + 1U);
  sample_storage duplicate = storage;
  duplicate.event.header.timestamp.ns = 123;
  duplicate.event.header.cpu_time.ns = 456;
  duplicate.event.header.flags = MITERUBY_EVENT_STACK_TRUNCATED | MITERUBY_EVENT_FROM_SIGNAL_HANDLER;
  duplicate.event.thread.value = Qtrue;
  memset((char *)duplicate.event.frames + data_size, 0xff, 4);
  assert(assert_dedup(&duplicate.event, false).offset == first.offset);
  assert(consumer_state.interned_events_pos == used);

  miteruby_frame_t first_frame = duplicate.event.frames[0];
  duplicate.event.frames[0] = duplicate.event.frames[1];
  duplicate.event.frames[1] = first_frame;
  bytecode_positions_for(&duplicate.event)[0].value = UINT16_MAX;
  bytecode_positions_for(&duplicate.event)[1].value = 12;
  assert(assert_dedup(&duplicate.event, true).offset != first.offset);

  bytecode_positions_for(event)[0].value++;
  miteruby_stack_dedup_id_t other_bytecode_pos = assert_dedup(event, true);
  assert(other_bytecode_pos.offset != first.offset);
  event->frames[0].cme = NULL;
  miteruby_stack_dedup_id_t other_cme = assert_dedup(event, true);
  assert(other_cme.offset != other_bytecode_pos.offset);
  event->frames[0].iseq = NULL;
  assert(assert_dedup(event, true).offset != other_cme.offset);
  event->header.frame_count = 1;
  assert(assert_dedup(event, true).offset != first.offset);

  event->header.frame_count = 0;
  used = consumer_state.interned_events_pos;
  miteruby_stack_dedup_id_t empty = assert_dedup(event, true);
  assert(empty.offset == used);
  assert(assert_dedup(event, false).offset == empty.offset);
  assert(consumer_state.interned_events_pos == used + 48);
  assert(get_stack(empty).frame_count == 0);
  assert(get_stack(first).frame_count == 2);
}

static void test_hash_collision_reuses_first_stack(void) {
  reset_stacks();
  sample_storage storage = {0};
  storage.event.header.frame_count = 1;
  bytecode_positions_for(&storage.event)[0].value = 12;
  miteruby_stack_hash_t stack_hash = miteruby_stack_hash(&storage.event);
  miteruby_stack_dedup_id_t first = assert_dedup(&storage.event, true);
  size_t used = consumer_state.interned_events_pos;

  bytecode_positions_for(&storage.event)[0].value = 13;
  // Supply the first stack's hash to simulate a collision with different stack contents.
  miteruby_stack_dedup_result_t result = reserve_stack(storage.event.header.frame_count, stack_hash);
  assert(!result.error_storage_full);
  assert(!result.ok.reserved);
  assert(result.ok.id.offset == first.offset);
  assert(consumer_state.interned_events_pos == used);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(stack_location_id(get_stack(first), 0).value.value == 12);
  reset_stacks();
}

static void test_fills_reserved_stack(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 2;
  event->frames[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->frames[1].iseq = (const rb_iseq_t *)&storage.words[15];
  bytecode_positions_for(event)[0].value = 19;
  bytecode_positions_for(event)[1].value = 27;
  miteruby_stack_dedup_id_t stack_id = assert_dedup(event, true);
  miteruby_stack_t stored = get_stack(stack_id);
  assert(stored.frame_count == 2);
  assert(stack_location_id(stored, 0).value.value == 19 && stack_location_id(stored, 1).value.value == 28);

  bytecode_positions_for(event)[0].value++;
  event->frames[0].cme = NULL;
  assert(stack_location_id(stored, 0).value.value == 19);
  assert(assert_dedup(event, true).offset != stack_id.offset);
  bytecode_positions_for(event)[0].value--;
  event->frames[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  assert(assert_dedup(event, false).offset == stack_id.offset);
}

static void test_map_growth_and_stable_storage(void) {
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 3;
  uint8_t *array = consumer_state.interned_events_queue;
  miteruby_stack_dedup_id_t ids[20000];
  for (uint16_t i = 0; i < 20000; i++) {
    bytecode_positions_for(event)[0].value = i;
    ids[i] = assert_dedup(event, true);
    assert(get_stack(ids[i]).end <= array + consumer_state.interned_events_pos);
    assert(array + consumer_state.interned_events_pos - get_stack(ids[i]).end < 8);
  }
  assert(miteruby_allocator_alloc_size(consumer_state.interned_events_queue) == INTERNED_EVENTS_QUEUE_MAX_SIZE);
  assert(consumer_state.interned_events_queue == array);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets) > 0);
  assert_allocation_accounting();

  size_t used = consumer_state.interned_events_pos;
  for (uint16_t i = 0; i < 20000; i++) {
    bytecode_positions_for(event)[0].value = i;
    assert(assert_dedup(event, false).offset == ids[i].offset);
    miteruby_stack_t stored = get_stack(ids[i]);
    assert(stored.frame_count == 3);
    assert(stack_location_id(stored, 0).value.value == i && stack_location_id(stored, 1).value.value == 1 && stack_location_id(stored, 2).value.value == 2);
  }
  assert(consumer_state.interned_events_pos == used);
  miteruby_stack_dedup_id_t empty = assert_dedup(&(miteruby_event_stack_sample_t) {0}, false);
  assert(get_stack(empty).frame_count == 0);
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
  size_t pos = consumer_state.interned_events_pos;
  uint8_t *array = consumer_state.interned_events_queue;
  miteruby_stack_hash_t stack_hash = miteruby_stack_hash(event);
  miteruby_stack_dedup_result_t result = reserve_stack(event->header.frame_count, stack_hash);
  if (!result.error_storage_full) {
    assert(result.ok.reserved);
    memset(result.ok.stack.ids, 0, event->header.frame_count * sizeof(*result.ok.stack.ids));
    assert(!commit_stack(result.ok.id, stack_hash, result.ok.stack.ids + event->header.frame_count));
  }
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == count);
  assert(consumer_state.interned_events_pos == pos);
  assert(consumer_state.interned_events_queue == array);
  for (
    verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_first(&stack_dedup_state.unique_stacks);
    !verstable_unique_stacks_map_is_end(entry);
    entry = verstable_unique_stacks_map_next(entry)
  ) {
    assert(entry.data->val.offset < pos);
  }
}

static void test_dedup_errors(void) {
  reset_stacks();
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
    bytecode_positions_for(event)[0].value = i;
    assert_dedup(event, true);
  }
  bytecode_positions_for(event)[0].value = 7;
  failed_allocation_name = "unique_stacks_map";
  assert_failed_dedup(event);
  event->frames[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  size_t events_count = buffered_event_count();
  size_t stacks_pos = consumer_state.interned_events_pos;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_DEDUP_STORAGE_FULL);
  assert(buffered_event_count() == events_count);
  assert(consumer_state.interned_events_pos == stacks_pos);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 7);
  size_t retained_count = consumer_state.mark_frame_array.count;
  miteruby_frame_id_t retained_id;
  assert(retain_frame(event->frames[0], &retained_id) == MITERUBY_CONSUMER_OK);
  assert(consumer_state.mark_frame_array.count == retained_count);
  failed_allocation_name = NULL;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  miteruby_stack_dedup_id_t stack_id = event_at(events_count)->stack_id;
  assert(stack_id.offset == stacks_pos);
  miteruby_stack_t stack = get_stack(stack_id);
  miteruby_location_t location = consumer_state.location_array.entries[stack_location_id(stack, 0).value.value];
  assert(location.frame_id.value == retained_id.value);
  assert(location.bytecode_pos.value == 7);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 8);
  failed_allocation_name = "unique_stacks_map";
  event->frames[0].cme = NULL;
  bytecode_positions_for(event)[0].value = 0;
  assert(assert_dedup(event, false).offset == 0);
  failed_allocation_name = NULL;
  assert_allocation_accounting();
}

static void test_unique_stacks_map_capacity(void) {
  reset_stacks();
  size_t count = 0;
  size_t upper_bound = UNIQUE_STACKS_MAP_MAX_SIZE / sizeof(*stack_dedup_state.unique_stacks.buckets);
  for (; count < upper_bound; count++) {
    verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_get_or_insert(
      &stack_dedup_state.unique_stacks, (miteruby_stack_hash_t) {.hash = count}, (miteruby_stack_dedup_id_t) {.offset = count}
    );
    if (verstable_unique_stacks_map_is_end(entry)) break;
  }
  assert(count > 20000 && count < upper_bound);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == count);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets) <= UNIQUE_STACKS_MAP_MAX_SIZE);
  miteruby_stack_dedup_result_t existing = reserve_stack(1, (miteruby_stack_hash_t) {.hash = 0});
  assert(!existing.error_storage_full && !existing.ok.reserved && existing.ok.id.offset == 0);
  assert_allocation_accounting();
}

static void test_fixed_array_capacity(void) {
  miteruby_consumer_reset();
  uint8_t *array = consumer_state.interned_events_queue;
  union {
    miteruby_event_stack_sample_t event;
    uint64_t words[MITERUBY_MAX_SIZE_BYTES / sizeof(uint64_t)];
  } full_storage = {0};
  miteruby_event_stack_sample_t *event = &full_storage.event;
  event->header.frame_count = MITERUBY_MAX_FRAMES;
  miteruby_bytecode_pos_t *bytecode_positions = bytecode_positions_for(event);
  size_t compact_stack_size = 1248;
  uint16_t bytecode_pos = 0;
  while (INTERNED_EVENTS_QUEUE_MAX_SIZE - consumer_state.interned_events_pos >= compact_stack_size) {
    bytecode_positions[0].value = bytecode_pos++;
    miteruby_stack_hash_t hash = miteruby_stack_hash(event);
    miteruby_stack_dedup_result_t result = reserve_stack(event->header.frame_count, hash);
    assert(!result.error_storage_full && result.ok.reserved);
    const uint8_t *end = fill_max_size_ids(result.ok.stack);
    assert(commit_stack(result.ok.id, hash, end));
  }

  bytecode_positions[0].value = bytecode_pos;
  assert_failed_dedup(event);
  size_t remaining = INTERNED_EVENTS_QUEUE_MAX_SIZE - consumer_state.interned_events_pos;
  assert(remaining < compact_stack_size);
  assert(miteruby_allocator_alloc_size(consumer_state.interned_events_queue) == 16U * 1024U * 1024U);
  assert(consumer_state.interned_events_queue == array);
  if (remaining >= sizeof(miteruby_event_deduped_sample_t)) {
    miteruby_stack_dedup_result_t last = reserve_stack(
      (uint16_t) ((remaining - offsetof(miteruby_event_deduped_sample_t, stack.ids)) / 3), (miteruby_stack_hash_t) {.hash = UINT64_MAX}
    );
    assert(!last.error_storage_full && last.ok.reserved);
    const uint8_t *end = fill_max_size_ids(last.ok.stack);
    assert(commit_stack(last.ok.id, (miteruby_stack_hash_t) {.hash = UINT64_MAX}, end));
  }
  assert(INTERNED_EVENTS_QUEUE_MAX_SIZE - consumer_state.interned_events_pos < sizeof(miteruby_event_deduped_sample_t));
  assert_failed_dedup(&(miteruby_event_stack_sample_t) {0});
  bytecode_positions[0].value = 0;
  assert(reserve_stack(event->header.frame_count, miteruby_stack_hash(event)).error_storage_full);

  sample_storage storage = {0};
  storage.event.thread.value = Qtrue;
  size_t previous_events_count = buffered_event_count();
  size_t previous_frame_count = verstable_mark_frame_set_size(&consumer_state.mark_frame_set);
  size_t previous_threads_count = verstable_mark_threads_set_size(&consumer_state.mark_threads_set);
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_INTERNED_EVENTS_QUEUE_FULL);
  assert(buffered_event_count() == previous_events_count);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == previous_threads_count);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == previous_frame_count);
  assert_allocation_accounting();
  assert_consumer_storage_full();

  reset_stacks();
  assert(assert_dedup(event, true).offset == 0);
  assert_allocation_accounting();
}

static void test_compact_events_and_reset(void) {
  miteruby_consumer_reset();
  assert_allocation_accounting();
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header = (miteruby_event_header_t) {
    .size_bytes = 72,
    .frame_count = 2,
    .flags = MITERUBY_EVENT_STACK_TRUNCATED | MITERUBY_EVENT_FROM_SIGNAL_HANDLER,
    .timestamp.ns = 123,
    .cpu_time.ns = 456,
  };
  event->thread.value = Qnil;
  event->frames[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->frames[0].iseq = (const rb_iseq_t *)&storage.words[15];
  event->frames[1] = event->frames[0];
  miteruby_location_t *locations = consumer_state.location_array.entries;
  uint8_t *queue = consumer_state.interned_events_queue;
  size_t capacity = consumer_state.interned_events_capacity / sizeof(miteruby_event_deduped_sample_t);
  assert(capacity == (16U * 1024U * 1024U) / sizeof(miteruby_event_deduped_sample_t));
  for (size_t i = 0; i < capacity; i++) {
    event->header.timestamp.ns = 123 + i;
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  }
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 1);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == 1);
  assert(buffered_event_count() == capacity);
  assert(consumer_state.interned_events_capacity == INTERNED_EVENTS_QUEUE_MAX_SIZE);
  assert(consumer_state.location_array.entries == locations && consumer_state.location_array.count == 1);
  assert(consumer_state.location_array.capacity == LOCATION_ARRAY_CAPACITY);
  assert(consumer_state.location_set.ctx == &consumer_state.location_array);
  assert(consumer_state.interned_events_queue == queue);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets) > 0);
  assert_allocation_accounting();
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  size_t stacks_pos = consumer_state.interned_events_pos;
  event->thread.value = Qtrue;
  bytecode_positions_for(event)[0].value++;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_INTERNED_EVENTS_QUEUE_FULL);
  assert(buffered_event_count() == capacity);
  assert(consumer_state.interned_events_capacity == INTERNED_EVENTS_QUEUE_MAX_SIZE);
  assert(consumer_state.location_array.entries == locations && consumer_state.location_array.count == 1);
  assert(consumer_state.location_array.capacity == LOCATION_ARRAY_CAPACITY);
  assert(consumer_state.location_set.ctx == &consumer_state.location_array);
  assert(consumer_state.interned_events_queue == queue);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(consumer_state.interned_events_pos == stacks_pos);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 1);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == 1);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
  bytecode_positions_for(event)[0].value--;

  for (size_t i = 0; i < capacity; i++) {
    const miteruby_event_deduped_sample_t *deduped = (const miteruby_event_deduped_sample_t *)(queue + i * sizeof(*deduped));
    assert(deduped->stack.frame_count == (i == 0 ? 2 : 0));
    assert(deduped->stack.ids_size == (i == 0 ? 2 : 0));
    assert(deduped->header.size_bytes == sizeof(*deduped));
    assert(deduped->header.frame_count == 2);
    assert(deduped->header.flags == event->header.flags);
    assert(deduped->header.timestamp.ns == (long)(123 + i));
    assert(deduped->header.cpu_time.ns == 456);
    assert(deduped->thread.value == Qnil && deduped->stack_id.offset == 0);
  }

  reset_stacks();
  event->thread.value = Qtrue;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 2);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == 1);

  miteruby_consumer_reset();
  assert_allocation_accounting();
  assert(buffered_event_count() == 0 && consumer_state.interned_events_pos == 0);
  assert(miteruby_allocator_alloc_size(consumer_state.interned_events_queue) == INTERNED_EVENTS_QUEUE_MAX_SIZE && consumer_state.interned_events_queue != NULL);
  assert(consumer_state.mark_frame_array.entries != NULL);
  assert(consumer_state.mark_frame_array.count == 0);
  assert(consumer_state.mark_frame_array.capacity == UINT16_MAX);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_frame_array.entries) ==
    consumer_state.mark_frame_array.capacity * sizeof(miteruby_frame_t));
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 0);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == 0);
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(event_at(0)->stack_id.offset == 0);
}

static void assert_allocator_limit(void *(*allocate)(size_t), void (*release)(void *, size_t), size_t limit) {
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  void *allocation = allocate(limit);
  assert(allocation != NULL);
  release(allocation, limit);
  assert(allocate(limit + 1) == NULL);
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);
}

static void assert_frame_id(miteruby_frame_t frame, uint32_t expected_id) {
  miteruby_frame_id_t id = {.value = (uint16_t) expected_id};
  verstable_mark_frame_set_itr entry = verstable_mark_frame_set_get(&consumer_state.mark_frame_set, id);
  assert(!verstable_mark_frame_set_is_end(entry));
  assert(entry.data->key.value == expected_id);
  miteruby_frame_t resolved = consumer_state.mark_frame_array.entries[id.value];
  assert(resolved.cme == frame.cme && resolved.iseq == frame.iseq);
}

static void assert_location_id(miteruby_frame_t frame, miteruby_bytecode_pos_t bytecode_pos, uint32_t expected_id) {
  size_t retained_count = consumer_state.mark_frame_array.count;
  miteruby_frame_id_t frame_id;
  assert(retain_frame(frame, &frame_id) == MITERUBY_CONSUMER_OK);
  assert(consumer_state.mark_frame_array.count == retained_count);
  miteruby_location_id_t id = {.value = {.value = expected_id}};
  verstable_location_set_itr entry = verstable_location_set_get(&consumer_state.location_set, id);
  assert(!verstable_location_set_is_end(entry));
  assert(entry.data->key.value.value == expected_id);
  miteruby_location_t location = consumer_state.location_array.entries[id.value.value];
  assert(location.frame_id.value == frame_id.value);
  assert(location.bytecode_pos.value == bytecode_pos.value);
}

static void test_frame_identity(void) {
  miteruby_consumer_reset();
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 1;
  event->thread.value = Qnil;
  const rb_callable_method_entry_t *cme = (const rb_callable_method_entry_t *)&storage.words[12];
  const rb_iseq_t *iseq = (const rb_iseq_t *)&storage.words[13];
  miteruby_frame_t pairs[] = {
    {.cme = cme, .iseq = iseq},
    {.cme = cme, .iseq = (const rb_iseq_t *)&storage.words[14]},
    {.cme = (const rb_callable_method_entry_t *)&storage.words[15], .iseq = iseq},
    {.cme = cme, .iseq = NULL},
    {.cme = NULL, .iseq = iseq},
  };
  size_t count = sizeof(pairs) / sizeof(*pairs);
  for (size_t i = 0; i < count; i++) {
    event->frames[0] = pairs[i];
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
    assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == i + 1);
    assert_frame_id(pairs[i], i);
    assert_location_id(pairs[i], bytecode_positions_for(event)[0], i);
    miteruby_stack_t stack = get_stack(event_at(i)->stack_id);
    assert(stack.frame_count == 1 && stack_location_id(stack, 0).value.value == i);
  }

  bytecode_positions_for(event)[0].value++;
  for (size_t i = 0; i < count; i++) {
    event->frames[0] = pairs[i];
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
    assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == count);
    assert_location_id(pairs[i], bytecode_positions_for(event)[0], count + i);
    miteruby_stack_t stack = get_stack(event_at(count + i)->stack_id);
    assert(stack.frame_count == 1 && stack_location_id(stack, 0).value.value == count + i);
  }

  assert(verstable_location_set_size(&consumer_state.location_set) == count * 2);
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  event->header.frame_count = 2;
  event->frames[1] = event->frames[0];
  bytecode_positions_for(event)[0].value = 1;
  bytecode_positions_for(event)[1].value = 1;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_location_set_size(&consumer_state.location_set) == count * 2);
  assert_location_id(event->frames[0], bytecode_positions_for(event)[0], count * 2 - 1);
  miteruby_stack_t repeated = get_stack(event_at(buffered_event_count() - 1)->stack_id);
  assert(repeated.frame_count == 2);
  assert(stack_location_id(repeated, 0).value.value == count * 2 - 1 && stack_location_id(repeated, 1).value.value == count * 2 - 1);
  event->header.frame_count = 1;

  event->frames[0] = (miteruby_frame_t) {0};
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_INVALID_FRAME);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == count);
  for (size_t i = 0; i < count; i++) {
    assert_frame_id(pairs[i], i);
  }

  miteruby_consumer_reset();
  event->frames[0] = pairs[count - 1];
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert_frame_id(event->frames[0], 0);
  assert_location_id(event->frames[0], bytecode_positions_for(event)[0], 0);
  assert(verstable_location_set_size(&consumer_state.location_set) == 1);
}

static void test_frame_context(void) {
  miteruby_frame_t first_entries[] = {
    {.cme = (const rb_callable_method_entry_t *)1},
    {.cme = (const rb_callable_method_entry_t *)2},
    {.cme = (const rb_callable_method_entry_t *)1},
  };
  miteruby_frame_t second_entries[] = {first_entries[1], first_entries[0], first_entries[1]};
  miteruby_mark_frame_array_t arrays[] = {
    {.entries = first_entries, .capacity = 3},
    {.entries = second_entries, .capacity = 3},
  };
  assert(sizeof(verstable_mark_frame_set_bucket) == 2);
  for (size_t i = 0; i < 2; i++) {
    verstable_mark_frame_set set;
    verstable_mark_frame_set_init(&set, &arrays[i]);
    verstable_mark_frame_set_itr entry = verstable_mark_frame_set_get_or_insert(&set, (miteruby_frame_id_t) {.value = 0});
    assert(!verstable_mark_frame_set_is_end(entry) && entry.data->key.value == 0);
    assert(verstable_mark_frame_set_is_end(verstable_mark_frame_set_get(&set, (miteruby_frame_id_t) {.value = 1})));
    assert(verstable_mark_frame_set_reserve(&set, 32));
    assert(set.ctx == &arrays[i]);
    entry = verstable_mark_frame_set_get_or_insert(&set, (miteruby_frame_id_t) {.value = 2});
    assert(!verstable_mark_frame_set_is_end(entry) && entry.data->key.value == 0);
    assert(verstable_mark_frame_set_size(&set) == 1);
    verstable_mark_frame_set_cleanup(&set);
  }
  assert_allocation_accounting();
}

static void test_frame_bulk_marking(void) {
  miteruby_consumer_reset();
  miteruby_mark_frame_array_t *array = &consumer_state.mark_frame_array;
  marked_start = marked_end = NULL;
  testing_consumer_mark = true;
  consumer_mark(&consumer_state);
  assert(marked_start == (const VALUE *)array->entries && marked_end == marked_start);

  miteruby_frame_id_t id;
  miteruby_frame_t frame = {.cme = (const rb_callable_method_entry_t *)1, .iseq = (const rb_iseq_t *)2};
  assert(retain_frame(frame, &id) == MITERUBY_CONSUMER_OK && id.value == 0);
  assert(retain_frame(frame, &id) == MITERUBY_CONSUMER_OK && id.value == 0);
  assert(array->count == 1);
  assert(array->entries[1].cme == frame.cme && array->entries[1].iseq == frame.iseq);
  consumer_mark(&consumer_state);
  assert(marked_start == (const VALUE *)array->entries);
  assert(marked_end == (const VALUE *)&array->entries[1]);

  miteruby_consumer_reset();
  marked_start = marked_end = NULL;
  consumer_mark(&consumer_state);
  assert(marked_start == (const VALUE *)array->entries && marked_end == marked_start);
  testing_consumer_mark = false;
  assert_allocation_accounting();
}

static void test_retention_failure(bool fail_threads, size_t retained_objects, uint16_t frame_count) {
  miteruby_consumer_reset();
  verstable_mark_threads_set_cleanup(&consumer_state.mark_threads_set);
  verstable_mark_frame_set_cleanup(&consumer_state.mark_frame_set);
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->thread.value = Qnil;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  if (fail_threads) {
    for (size_t i = 0; i < retained_objects - 1; i++) assert(retain_thread(LONG2FIX(i)));
  } else {
    for (size_t i = 0; i < retained_objects; i++) {
      assert(retain_frame((miteruby_frame_t) {.cme = (const rb_callable_method_entry_t *)LONG2FIX(i)}, &(miteruby_frame_id_t) {0}) == MITERUBY_CONSUMER_OK);
    }
  }
  size_t stacks_pos = consumer_state.interned_events_pos;

  event->thread.value = LONG2FIX(100);
  event->header.frame_count = frame_count;
  event->frames[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  event->frames[0].iseq = (const rb_iseq_t *)&storage.words[15];
  if (frame_count > 1) event->frames[1].cme = event->frames[0].cme;
  failed_allocation_name = fail_threads ? "mark_threads" : "mark_frame";
  assert(buffer_event(&event->header) ==
    (fail_threads ? MITERUBY_CONSUMER_MARK_THREADS_FULL : MITERUBY_CONSUMER_MARK_FRAME_FULL));
  failed_allocation_name = NULL;

  assert(buffered_event_count() == 1);
  assert(event_at(0)->thread.value == Qnil);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 1);
  assert(consumer_state.interned_events_pos == stacks_pos);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == (fail_threads ? 7U : 2U));
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == (fail_threads ? 0U : 7U));
  assert_allocation_accounting();
  assert(assert_dedup(&(miteruby_event_stack_sample_t) {0}, false).offset == 0);
  thrd_t thread;
  assert(thrd_create(&thread, check_consumer_mutex_unlocked, NULL) == thrd_success);
  int result;
  assert(thrd_join(thread, &result) == thrd_success && result == 0);

  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(buffered_event_count() == 2);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == (frame_count ? 2U : 1U));
  assert(!verstable_mark_threads_set_is_end(verstable_mark_threads_set_get(&consumer_state.mark_threads_set, event->thread.value)));
  for (uint16_t i = 0; i < frame_count; i++) {
    assert_frame_id(event->frames[i], (fail_threads ? 0 : retained_objects) + i);
    miteruby_stack_t stack = get_stack(event_at(1)->stack_id);
    assert(stack_location_id(stack, i).value.value == i);
    miteruby_location_t location = consumer_state.location_array.entries[stack_location_id(stack, i).value.value];
    assert(location.frame_id.value == (fail_threads ? 0 : retained_objects) + i);
    assert(location.bytecode_pos.value == bytecode_positions_for(event)[i].value);
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

static void test_mark_frame_capacity(void) {
  size_t initial_size = miteruby_allocator_alloc_size(consumer_state.mark_frame_set.buckets);
  size_t count = 0;
  size_t upper_bound = (size_t) UINT16_MAX + 2;
  while (count < upper_bound && retain_frame((miteruby_frame_t) {.cme = (const rb_callable_method_entry_t *)(count + 1)}, &(miteruby_frame_id_t) {0}) == MITERUBY_CONSUMER_OK) count++;
  assert(count == MARK_FRAME_ARRAY_CAPACITY);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_frame_set.buckets) > initial_size);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_frame_set.buckets) <= MARK_FRAME_MAX_SIZE);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == count);
  assert_allocation_accounting();
  size_t allocated_bytes = miteruby_allocator_requested_bytes();
  for (size_t i = 0; i < count; i++) {
    miteruby_frame_t frame = {.cme = (const rb_callable_method_entry_t *)(i + 1)};
    miteruby_frame_id_t id = {.value = 123};
    assert(retain_frame(frame, &id) == MITERUBY_CONSUMER_MARK_FRAME_FULL);
    assert(id.value == 123);
    assert_frame_id(frame, i);
  }
  assert(miteruby_allocator_requested_bytes() == allocated_bytes);

  sample_storage storage = {0};
  storage.event.header.frame_count = 1;
  storage.event.thread.value = Qnil;
  storage.event.frames[0].cme = (const rb_callable_method_entry_t *)(count + 1);
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_MARK_FRAME_FULL);
  assert(buffered_event_count() == 0);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(consumer_state.interned_events_pos == 0);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == count);

  storage.event.frames[0].cme = (const rb_callable_method_entry_t *)count;
  bytecode_positions_for(&storage.event)[0].value = UINT16_MAX;
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_MARK_FRAME_FULL);
  assert(buffered_event_count() == 0);
  assert_frame_storage_full();
}

static miteruby_raw_events_queue_t invalid_raw_events_queue;

static VALUE consume_invalid_raw_events_queue(DDTRACE_UNUSED VALUE unused) {
  miteruby_consumer_consume_loop(&invalid_raw_events_queue);
  return Qnil;
}

static void assert_frame_storage_full(void) {
  sample_storage storage = {0};
  storage.event.header = (miteruby_event_header_t) {.frame_count = 1, .size_bytes = 56};
  storage.event.thread.value = Qnil;
  storage.event.frames[0].cme = (const rb_callable_method_entry_t *)1;
  assert(miteruby_raw_events_queue_init(&invalid_raw_events_queue) == 0);
  assert(miteruby_raw_events_queue_try_write(&invalid_raw_events_queue, storage.words, storage.event.header.size_bytes / 8, NULL));
  assert_runtime_error(consume_invalid_raw_events_queue, "Miteruby mark_frame storage is full");
  sigset_t mask;
  assert(pthread_sigmask(SIG_BLOCK, NULL, &mask) == 0);
  assert(sigismember(&mask, SIGPROF) == 0);
  miteruby_raw_events_queue_destroy(&invalid_raw_events_queue);
}

static void assert_consumer_storage_full(void) {
  sample_storage storage = {0};
  storage.event.header.size_bytes = sizeof(miteruby_event_stack_sample_t);
  storage.event.thread.value = Qnil;
  assert(miteruby_raw_events_queue_init(&invalid_raw_events_queue) == 0);
  assert(miteruby_raw_events_queue_try_write(&invalid_raw_events_queue, storage.words, storage.event.header.size_bytes / 8, NULL));
  assert_runtime_error(consume_invalid_raw_events_queue, "Miteruby interned events queue is full");
  sigset_t mask;
  assert(pthread_sigmask(SIG_BLOCK, NULL, &mask) == 0);
  assert(sigismember(&mask, SIGPROF) == 0);
  miteruby_raw_events_queue_destroy(&invalid_raw_events_queue);
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

static void test_invalid_frame(void) {
  miteruby_consumer_reset();
  sample_storage storage = {0};
  storage.event.header = (miteruby_event_header_t) {
    .size_bytes = 72, .frame_count = 2,
  };
  storage.event.thread.value = Qnil;
  storage.event.frames[0].cme = (const rb_callable_method_entry_t *)&storage.words[14];
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_INVALID_FRAME);
  assert(consumer_state.interned_events_pos == 0);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert(verstable_mark_frame_set_size(&consumer_state.mark_frame_set) == 1);
  assert_frame_id(storage.event.frames[0], 0);
  assert(verstable_mark_threads_set_size(&consumer_state.mark_threads_set) == 1);
  assert(buffered_event_count() == 0);

  storage.event.frames[1].cme = (const rb_callable_method_entry_t *)&storage.words[15];
  assert(buffer_event(&storage.event.header) == MITERUBY_CONSUMER_OK);
  assert(event_at(0)->stack_id.offset == 0);
  assert_frame_id(storage.event.frames[0], 0);
  assert_frame_id(storage.event.frames[1], 1);
  storage.event.frames[1].cme = NULL;
  miteruby_consumer_reset();

  assert(miteruby_raw_events_queue_init(&invalid_raw_events_queue) == 0);
  assert(miteruby_raw_events_queue_try_write(&invalid_raw_events_queue, storage.words, 9, NULL));
  assert_runtime_error(consume_invalid_raw_events_queue, "Miteruby invalid frame: both CME and ISEQ are NULL");
  assert(buffered_event_count() == 0);
  assert(consumer_state.interned_events_pos == 0);
  miteruby_raw_events_queue_destroy(&invalid_raw_events_queue);
  miteruby_consumer_reset();
}

static void test_location_set(void) {
  miteruby_consumer_reset();
  verstable_location_set *set = &consumer_state.location_set;
  miteruby_location_array_t *array = &consumer_state.location_array;
  assert(verstable_location_set_size(set) == 0 && array->count == 0);
  assert(sizeof(*set->buckets) == 4);
  assert(sizeof(*array->entries) == 4);
  assert(set->ctx == array);
  miteruby_location_t location = {.frame_id = {.value = UINT16_MAX}, .bytecode_pos = {.value = UINT16_MAX}};
  miteruby_location_id_t id;
  assert(intern_location(location, &id) == MITERUBY_CONSUMER_OK && id.value.value == 0);
  miteruby_location_t resolved = consumer_state.location_array.entries[id.value.value];
  assert(resolved.frame_id.value == UINT16_MAX && resolved.bytecode_pos.value == UINT16_MAX);

  assert(intern_location(location, &id) == MITERUBY_CONSUMER_OK && id.value.value == 0);
  assert(array->count == 1 && verstable_location_set_size(set) == 1);
  location.bytecode_pos.value--;
  assert(intern_location(location, &id) == MITERUBY_CONSUMER_OK && id.value.value == 1);
  location.bytecode_pos.value++;
  location.frame_id.value--;
  assert(intern_location(location, &id) == MITERUBY_CONSUMER_OK && id.value.value == 2);
  assert(array->count == 3);
  assert(verstable_location_set_reserve(set, 1024));
  assert(set->ctx == array);
  for (unsigned int i = 0; i < array->count; i++) {
    assert(intern_location(array->entries[i], &id) == MITERUBY_CONSUMER_OK && id.value.value == i);
  }
  assert_allocation_accounting();

  miteruby_consumer_reset();
  assert(verstable_location_set_size(set) == 0 && array->count == 0);
  assert(set->ctx == array);
  assert(intern_location(location, &id) == MITERUBY_CONSUMER_OK && id.value.value == 0);
  assert_allocation_accounting();
}

static void test_location_interning_failure(void) {
  miteruby_consumer_reset();
  verstable_location_set_cleanup(&consumer_state.location_set);
  sample_storage storage = {0};
  miteruby_event_stack_sample_t *event = &storage.event;
  event->header.frame_count = 1;
  event->thread.value = Qnil;
  event->frames[0].iseq = (const rb_iseq_t *)&storage.words[15];
  failed_allocation_name = "location_set";
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_LOCATION_STORAGE_FULL);
  assert(buffered_event_count() == 0);
  assert(consumer_state.interned_events_pos == 0);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 0);
  assert_frame_id(event->frames[0], 0);
  assert(verstable_location_set_size(&consumer_state.location_set) == 0 && consumer_state.location_array.count == 0);
  failed_allocation_name = NULL;

  for (uint16_t i = 0; i < 6; i++) {
    bytecode_positions_for(event)[0].value = i;
    assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
    assert_location_id(event->frames[0], bytecode_positions_for(event)[0], i);
  }
  size_t stacks_pos = consumer_state.interned_events_pos;
  event->header.frame_count = 2;
  event->frames[1] = event->frames[0];
  bytecode_positions_for(event)[0].value = 6;
  bytecode_positions_for(event)[1].value = 7;
  failed_allocation_name = "location_set";
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_LOCATION_STORAGE_FULL);
  assert(buffered_event_count() == 6);
  assert(consumer_state.interned_events_pos == stacks_pos);
  assert(verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) == 6);
  assert(verstable_location_set_size(&consumer_state.location_set) == 7 && consumer_state.location_array.count == 7);
  assert_location_id(event->frames[0], bytecode_positions_for(event)[0], 6);

  bytecode_positions_for(event)[1].value = 6;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert(verstable_location_set_size(&consumer_state.location_set) == 7 && consumer_state.location_array.count == 7);
  failed_allocation_name = NULL;
  bytecode_positions_for(event)[1].value = 7;
  assert(buffer_event(&event->header) == MITERUBY_CONSUMER_OK);
  assert_location_id(event->frames[1], bytecode_positions_for(event)[1], 7);
  assert_allocation_accounting();
  miteruby_consumer_reset();
}

static void test_location_array_capacity(void) {
  miteruby_consumer_reset();
  miteruby_location_array_t *array = &consumer_state.location_array;
  for (unsigned int i = 0; i < LOCATION_ARRAY_CAPACITY; i++) {
    miteruby_location_t location = {
      .frame_id = {.value = (uint16_t) i},
      .bytecode_pos = {.value = (uint16_t) (i >> 16)},
    };
    miteruby_location_id_t id = {.value = {.value = UINT20_MAX}};
    assert(intern_location(location, &id) == MITERUBY_CONSUMER_OK && id.value.value == i);
  }
  assert(array->count == LOCATION_ARRAY_CAPACITY);
  assert(verstable_location_set_size(&consumer_state.location_set) == array->count);
  assert(miteruby_allocator_alloc_size(consumer_state.location_set.buckets) <= LOCATION_SET_MAX_SIZE);
  for (unsigned int i = 0; i < array->count; i++) {
    miteruby_location_id_t id = {.value = {.value = i}};
    miteruby_location_t location = consumer_state.location_array.entries[id.value.value];
    assert(location.frame_id.value == (uint16_t) i && location.bytecode_pos.value == (uint16_t) (i >> 16));
    verstable_location_set_itr entry = verstable_location_set_get(&consumer_state.location_set, id);
    assert(!verstable_location_set_is_end(entry) && entry.data->key.value.value == i);
  }
  miteruby_location_id_t id = {.value = {.value = UINT20_MAX}};
  assert(intern_location((miteruby_location_t) {0}, &id) == MITERUBY_CONSUMER_LOCATION_STORAGE_FULL);
  assert(id.value.value == UINT20_MAX);
  assert(intern_location((miteruby_location_t) {.bytecode_pos = {.value = UINT16_MAX}}, &id) == MITERUBY_CONSUMER_LOCATION_STORAGE_FULL);
  assert(id.value.value == UINT20_MAX && array->count == LOCATION_ARRAY_CAPACITY);

  sample_storage storage = {0};
  storage.event.header = (miteruby_event_header_t) {.frame_count = 1, .size_bytes = 56};
  storage.event.thread.value = Qnil;
  storage.event.frames[0].cme = (const rb_callable_method_entry_t *)1;
  assert(miteruby_raw_events_queue_init(&invalid_raw_events_queue) == 0);
  assert(miteruby_raw_events_queue_try_write(&invalid_raw_events_queue, storage.words, storage.event.header.size_bytes / 8, NULL));
  assert_runtime_error(consume_invalid_raw_events_queue, "Miteruby location storage is full");
  sigset_t mask;
  assert(pthread_sigmask(SIG_BLOCK, NULL, &mask) == 0);
  assert(sigismember(&mask, SIGPROF) == 0);
  miteruby_raw_events_queue_destroy(&invalid_raw_events_queue);
  assert(buffered_event_count() == 0);
  assert_allocation_accounting();
  miteruby_consumer_reset();
}

static void test_compressed_stack_storage(void) {
  reset_stacks();
  uint20_t values[] = {{.value = 0}, {.value = 0}, {.value = UINT20_MAX}, {.value = 0}, {.value = 64}, {.value = 63}, {.value = 8192}};
  const uint8_t expected[] = {0, 0, 0xfe, 0xff, 0x7f, 0xfd, 0xff, 0x7f, 0x80, 1, 1, 0x82, 0x7f};
  miteruby_stack_hash_t hash = {.hash = 1};
  miteruby_stack_dedup_result_t result = reserve_stack(7, hash);
  assert(!result.error_storage_full && result.ok.reserved);
  assert(result.ok.stack.end - result.ok.stack.ids == 21);
  uint8_t *cursor = result.ok.stack.ids;
  uint20_t previous = {0};
  for (size_t i = 0; i < 7; i++) {
    assert(miteruby_compressed_deltas_write(previous, values[i], &cursor, result.ok.stack.end));
    previous = values[i];
  }
  assert(commit_stack(result.ok.id, hash, cursor));
  miteruby_stack_t stored = get_stack(result.ok.id);
  assert((size_t) (stored.end - stored.ids) == sizeof(expected));
  assert(memcmp(stored.ids, expected, sizeof(expected)) == 0);
  assert(consumer_state.interned_events_pos == 64);
  for (uint16_t i = 0; i < 7; i++) assert(stack_location_id(stored, i).value.value == values[i].value);

  hash.hash++;
  result = reserve_stack(1, hash);
  assert(!result.error_storage_full && result.ok.reserved && result.ok.id.offset == 64);
  cursor = result.ok.stack.ids;
  assert(miteruby_compressed_deltas_write((uint20_t) {0}, (uint20_t) {.value = 1}, &cursor, result.ok.stack.end));
  assert(commit_stack(result.ok.id, hash, cursor));
  assert(stack_location_id(get_stack(result.ok.id), 0).value.value == 1);
  assert(consumer_state.interned_events_pos == 112);
  assert(stack_location_id(stored, 6).value.value == 8192);
  size_t pos = consumer_state.interned_events_pos;
  size_t capacity = pos + sizeof(miteruby_event_deduped_sample_t);
  result = miteruby_stack_dedup_get_or_reserve(7, (miteruby_stack_hash_t) {.hash = 3}, consumer_state.interned_events_queue, pos, capacity);
  assert(result.error_storage_full);
  result = miteruby_stack_dedup_get_or_reserve(7, (miteruby_stack_hash_t) {.hash = 1}, consumer_state.interned_events_queue, pos, capacity);
  assert(!result.error_storage_full && !result.ok.reserved && result.ok.id.offset == 0);
  miteruby_event_deduped_sample_t *duplicate = (miteruby_event_deduped_sample_t *)(consumer_state.interned_events_queue + pos);
  assert(duplicate->header.size_bytes == 48 && duplicate->stack.frame_count == 0 && duplicate->stack.ids_size == 0);
  assert(stack_location_id(get_stack(result.ok.id), 6).value.value == 8192);
  reset_stacks();
}

int main(int argc, char **argv) {
  ruby_sysinit(&argc, &argv);
  RUBY_INIT_STACK;
  ruby_init();
  test_raw_events_queue_internal_error();
  initialize_consumer(Qnil);
  miteruby_consumer_reset();
  assert(miteruby_allocator_alloc_size(consumer_state.interned_events_queue) == INTERNED_EVENTS_QUEUE_MAX_SIZE && consumer_state.interned_events_queue != NULL);
  assert_allocation_accounting();
  test_invalid_frame();
  test_hash_collision_reuses_first_stack();
  test_compressed_stack_storage();
  test_empty_stack_before_nonempty();
  test_stack_identity();
  test_fills_reserved_stack();
  test_map_growth_and_stable_storage();
  miteruby_consumer_reset();
  test_dedup_errors();
  test_unique_stacks_map_capacity();
  test_fixed_array_capacity();
  test_compact_events_and_reset();
  test_frame_identity();
  test_frame_context();
  test_frame_bulk_marking();
  test_location_set();
  test_location_interning_failure();
  test_location_array_capacity();
  test_reset_failure("interned_events_queue", "Failed to allocate miteruby.interned_events_queue");
  test_reset_failure("mark_frame_array", "Failed to allocate miteruby.mark_frame_array");
  test_reset_failure("location_array", "Failed to allocate miteruby.location_array");
  assert_allocator_limit(mark_threads_calloc, miteruby_allocator_free_sized, MARK_THREADS_MAX_SIZE);
  assert_allocator_limit(mark_frame_calloc, miteruby_allocator_free_sized, MARK_FRAME_MAX_SIZE);
  assert_allocator_limit(location_calloc, miteruby_allocator_free_sized, LOCATION_SET_MAX_SIZE);
  assert_allocator_limit(unique_stacks_calloc, miteruby_allocator_free_sized, UNIQUE_STACKS_MAP_MAX_SIZE);
  test_retention_failure(true, 7, 0);
  test_retention_failure(true, 7, 1);
  test_retention_failure(false, 7, 1);
  test_retention_failure(false, 6, 2);
  miteruby_consumer_reset();
  assert(buffered_event_count() == 0);
  assert(consumer_state.interned_events_pos == 0);
  test_mark_threads_capacity();
  test_mark_frame_capacity();
  verstable_unique_stacks_map_cleanup(&stack_dedup_state.unique_stacks);
  verstable_mark_threads_set_cleanup(&consumer_state.mark_threads_set);
  verstable_mark_frame_set_cleanup(&consumer_state.mark_frame_set);
  verstable_location_set_cleanup(&consumer_state.location_set);
  assert(miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets) == 0);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_threads_set.buckets) == 0);
  assert(miteruby_allocator_alloc_size(consumer_state.mark_frame_set.buckets) == 0);
  miteruby_allocator_free(&consumer_state.interned_events_queue);
  miteruby_allocator_free(&consumer_state.mark_frame_array.entries);
  miteruby_allocator_free(&consumer_state.location_array.entries);
  miteruby_raw_events_queue_destroy(consumer_state.raw_events_queue);
  miteruby_allocator_free(&consumer_state.raw_events_queue);
  assert(miteruby_allocator_requested_bytes() == 0);
  mtx_destroy(&consumer_state.mutex);
  puts("Miteruby consumer tests passed");
  return ruby_cleanup(0);
}
