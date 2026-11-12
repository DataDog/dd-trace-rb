#include "stack_dedup.h"
#include "allocator.h"
#include "compressed_deltas.h"
#include "hashtable/rapidhash.h"
#include "../datadog_ruby_common.h"
#include "../helpers.h"

#include <stdlib.h>
#include <string.h>

// The 16 MiB event queue holds at most 349,525 unique stacks (48 bytes minimum per event), fitting in 524,288 map buckets.
// 16-byte hash/offset pairs plus metadata need just over 9 MiB.
#define UNIQUE_STACKS_MAP_MAX_SIZE MiB_AS_BYTES(10)

static uint64_t stack_hash_value(miteruby_stack_hash_t key);
static bool stack_hash_equal(miteruby_stack_hash_t left, miteruby_stack_hash_t right);
static void *unique_stacks_calloc(size_t size);

#define NAME verstable_unique_stacks_map
#define KEY_TY miteruby_stack_hash_t
#define VAL_TY miteruby_stack_dedup_id_t
#define HASH_FN stack_hash_value
#define CMPR_FN stack_hash_equal
#define MALLOC_FN unique_stacks_calloc
#define FREE_FN miteruby_allocator_free_sized
#include "hashtable/verstable.h"

// Stack deduping design
//
// New stacks live inline in their first sample in the consumer's `interned_events_queue`.
// Later samples store the same stack_id and a zeroed inline stack header, with no IDs.
// `verstable_unique_stacks_map` maps stack hashes to the byte offset of that first sample.
// Each stack starts its deltas from 0. Sample sizes are rounded to 8 bytes to align the next event header.
//
// Here's how it looks as an example (each letter is a CME/ISEQ pair):
// * Input:
//   * Event 1: [A, B, C, D, 0, 1, 2, 3] (frame_count: 4)
//   * Event 2: [E, F, 0, 1] (frame_count: 2)
//   * Event 3: [A, B, C, D, 0, 1, 2, 3] (frame_count: 4)
//
// * Interned events queue (assuming these locations get IDs 0 through 5):
//   [ Event 1 | stack_id: 0  | frame_count: 4 | ids_size: 4 | 00 02 02 02 ]
//   [ Event 2 | stack_id: 48 | frame_count: 2 | ids_size: 2 | 08 02 | padding ]
//   [ Event 3 | stack_id: 0  | frame_count: 0 | ids_size: 0 | padding ]
//
//   Conceptually, those bytes represent:
//   [ Event 1 | stack_id: 0  | (A, 0) (B, 1) (C, 2) (D, 3) ]
//   [ Event 2 | stack_id: 48 | (E, 0) (F, 1) ]
//   [ Event 3 | stack_id: 0  |              ]
//
// * Unique stacks map:
//   hash(A B C D; 0 1 2 3) -> stack_id:  0  (Events 1 and 3)
//   hash(E F; 0 1)         -> stack_id: 48  (Event 2)
//
// The map must be cleared before the consumer reuses the event storage after serialization or reset.
typedef struct {
  verstable_unique_stacks_map unique_stacks;
} miteruby_stack_dedup_state_t;

static miteruby_stack_dedup_state_t stack_dedup_state = {0};

miteruby_stack_hash_t miteruby_stack_hash(const miteruby_event_stack_sample_t *event) {
  size_t size = event->header.frame_count * (sizeof(miteruby_frame_t) + sizeof(miteruby_bytecode_pos_t));
  return (miteruby_stack_hash_t) {.hash = rapidhash(event->frames, size)};
}

static uint64_t stack_hash_value(miteruby_stack_hash_t key) {
  return key.hash;
}

static bool stack_hash_equal(miteruby_stack_hash_t left, miteruby_stack_hash_t right) {
  return left.hash == right.hash;
}

static void *unique_stacks_calloc(size_t size) {
  if (size > UNIQUE_STACKS_MAP_MAX_SIZE) return NULL;

  return miteruby_allocator_alloc(size, "unique_stacks_map");
}

void miteruby_stack_dedup_init(void) {
  verstable_unique_stacks_map_init(&stack_dedup_state.unique_stacks);
}

void miteruby_stack_dedup_reset(void) {
  verstable_unique_stacks_map_clear(&stack_dedup_state.unique_stacks);
}

size_t miteruby_stack_dedup_size(void) {
  return sizeof(stack_dedup_state.unique_stacks) + miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets);
}

miteruby_stack_dedup_stats_t miteruby_stack_dedup_stats(void) {
  return (miteruby_stack_dedup_stats_t) {
    .map_max_size_bytes = UNIQUE_STACKS_MAP_MAX_SIZE,
    .map_entries = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks),
  };
}

miteruby_stack_t miteruby_stack_dedup_get(uint8_t *events, miteruby_stack_dedup_id_t stack_id) {
  miteruby_event_deduped_sample_t *event = (miteruby_event_deduped_sample_t *)(events + stack_id.offset);
  miteruby_stored_stack_t *stack = &event->stack;
  return (miteruby_stack_t) {
    .frame_count = stack->frame_count,
    .ids = stack->ids,
    .end = stack->ids + stack->ids_size,
  };
}

miteruby_stack_dedup_result_t miteruby_stack_dedup_get_or_reserve(
  uint16_t frame_count, miteruby_stack_hash_t stack_hash, uint8_t *events, size_t events_pos, size_t events_capacity
) {
  if (events_capacity - events_pos < sizeof(miteruby_event_deduped_sample_t)) {
    return (miteruby_stack_dedup_result_t) {.error_storage_full = true};
  }

  miteruby_event_deduped_sample_t *event = (miteruby_event_deduped_sample_t *)(events + events_pos);
  event->stack.frame_count = 0;
  event->stack.ids_size = 0;
  event->header.size_bytes = sizeof(miteruby_event_deduped_sample_t);

  verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_get(&stack_dedup_state.unique_stacks, stack_hash);
  if (!verstable_unique_stacks_map_is_end(entry)) {
    return (miteruby_stack_dedup_result_t) {.ok = {.id = entry.data->val, .reserved = false}};
  }

  size_t max_ids_size = miteruby_compressed_deltas_max_size_of(frame_count);
  size_t max_event_size = (offsetof(miteruby_event_deduped_sample_t, stack.ids) + max_ids_size + 7) & ~(size_t) 7;
  if (max_event_size > UINT16_MAX || events_capacity - events_pos < max_event_size) {
    return (miteruby_stack_dedup_result_t) {.error_storage_full = true};
  }

  event->stack.frame_count = frame_count;
  return (miteruby_stack_dedup_result_t) {.ok = {
    .id = {.offset = events_pos},
    .reserved = true,
    .stack = {.frame_count = frame_count, .ids = event->stack.ids, .end = event->stack.ids + max_ids_size},
  }};
}

bool miteruby_stack_dedup_commit(
  uint8_t *events, miteruby_stack_dedup_id_t stack_id, miteruby_stack_hash_t stack_hash, const uint8_t *ids_end
) {
  verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_get_or_insert(&stack_dedup_state.unique_stacks, stack_hash, stack_id);
  if (verstable_unique_stacks_map_is_end(entry)) return false;

  miteruby_event_deduped_sample_t *event = (miteruby_event_deduped_sample_t *)(events + stack_id.offset);
  event->stack.ids_size = (uint16_t) (ids_end - event->stack.ids);
  event->header.size_bytes = (uint16_t) ((offsetof(miteruby_event_deduped_sample_t, stack.ids) + event->stack.ids_size + 7) & ~(size_t) 7);
  return true;
}
