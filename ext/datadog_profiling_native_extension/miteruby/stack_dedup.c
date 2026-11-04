#include "stack_dedup.h"
#include "allocator.h"
#include "hashtable/rapidhash.h"
#include "../datadog_ruby_common.h"
#include "../helpers.h"

#include <stdlib.h>
#include <string.h>

#define UNIQUE_STACKS_ARRAY_MAX_SIZE MiB_AS_BYTES(16)
#define UNIQUE_STACKS_MAP_MAX_SIZE MiB_AS_BYTES(16)

typedef struct {
  uint16_t frame_count;
  miteruby_location_id_t ids[];
} miteruby_stored_stack_t;

_Static_assert(offsetof(miteruby_stored_stack_t, ids) == 4, "miteruby_stored_stack_t IDs must start after a 4-byte prefix");

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
// We keep two data structures:
//
// * `unique_stacks_array`: Contiguous storage of frame counts followed by location IDs.
// The 4-byte prefix and 4-byte IDs keep consecutive records aligned without trailing padding.
//
// * `verstable_unique_stacks_map`: Maps stack hashes to IDs (byte offsets in `unique_stacks_array`).
//
// Here's how it looks as an example (each letter is a CME/ISEQ pair):
// * Input:
//   * Event 1: [A, B, C, D, 0, 1, 2, 3] (frame_count: 4)
//   * Event 2: [E, F, 0, 1] (frame_count: 2)
//   * Event 3: [A, B, C, D, 0, 1, 2, 3] (frame_count: 4)
//
// * Unique stacks array (id(X, p) is the location ID for CME/ISEQ pair X at position p):
//   [ frame_count: 4 | id(A, 0) | id(B, 1) | id(C, 2) | id(D, 3) | frame_count: 2 | id(E, 0) | id(F, 1) ]
//     ^                                                          ^
//     |                                                          |
//     Events 1 and 3                                             Event 2
//
// * Unique stacks map:
//   hash(A B C D; 0 1 2 3) -> stack_id:  0  (Events 1 and 3)
//   hash(E F; 0 1)         -> stack_id: 20  (Event 2)
//
// Both of the above data structures are allocated with the miteruby allocator, since they're expected to be large and
// we want to manage them carefully.
//
// Even though conceptually CME and ISEQs are VALUEs that need marking for Ruby GC, the consumer tracks them separately
// in `verstable_mark_cme_iseq_map` so we don't need to mark them again here.

typedef struct {
  verstable_unique_stacks_map unique_stacks;

  uint8_t *unique_stacks_array;
  size_t unique_stacks_pos;
} miteruby_stack_dedup_state_t;

static miteruby_stack_dedup_state_t stack_dedup_state = {0};

miteruby_stack_hash_t miteruby_stack_hash(const miteruby_event_stack_sample_t *event) {
  size_t size = event->header.frame_count * (sizeof(miteruby_event_frame_refs_t) + sizeof(miteruby_event_frame_position_t));
  return (miteruby_stack_hash_t) {.hash = rapidhash(event->refs, size)};
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

bool miteruby_stack_dedup_init(void) {
  verstable_unique_stacks_map_init(&stack_dedup_state.unique_stacks);
  return miteruby_stack_dedup_reset();
}

bool miteruby_stack_dedup_reset(void) {
  uint8_t *new_array = miteruby_allocator_alloc(UNIQUE_STACKS_ARRAY_MAX_SIZE, "unique_stacks_array");
  if (new_array == NULL) return false;

  verstable_unique_stacks_map_clear(&stack_dedup_state.unique_stacks);
  miteruby_allocator_free(stack_dedup_state.unique_stacks_array);

  stack_dedup_state.unique_stacks_array = new_array;
  stack_dedup_state.unique_stacks_pos = 0;

  return true;
}

size_t miteruby_stack_dedup_size(void) {
  return sizeof(stack_dedup_state.unique_stacks) + miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) +
    miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks.buckets);
}

miteruby_stack_dedup_stats_t miteruby_stack_dedup_stats(void) {
  return (miteruby_stack_dedup_stats_t) {
    .array_max_size_bytes = UNIQUE_STACKS_ARRAY_MAX_SIZE,
    .array_used_size_bytes = stack_dedup_state.unique_stacks_pos,
    .map_max_size_bytes = UNIQUE_STACKS_MAP_MAX_SIZE,
    .map_entries = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks),
  };
}

miteruby_stack_t miteruby_stack_dedup_get(miteruby_stack_dedup_id_t stack_id) {
  miteruby_stored_stack_t *stack = (miteruby_stored_stack_t *)(stack_dedup_state.unique_stacks_array + stack_id.offset);
  return (miteruby_stack_t) {
    .frame_count = stack->frame_count,
    .ids = stack->ids,
  };
}

static size_t stored_stack_size(uint16_t frame_count) {
  return sizeof(miteruby_stored_stack_t) + frame_count * sizeof(miteruby_location_id_t);
}

miteruby_stack_dedup_result_t miteruby_stack_dedup_get_or_reserve(uint16_t frame_count, miteruby_stack_hash_t stack_hash) {
  verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_get(&stack_dedup_state.unique_stacks, stack_hash);
  if (!verstable_unique_stacks_map_is_end(entry)) {
    return (miteruby_stack_dedup_result_t) {.ok = {.id = entry.data->val, .reserved = false}};
  }

  if (miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) - stack_dedup_state.unique_stacks_pos < stored_stack_size(frame_count)) {
    return (miteruby_stack_dedup_result_t) {.error_storage_full = true};
  }

  miteruby_stack_dedup_id_t next_stack_id = {.offset = stack_dedup_state.unique_stacks_pos};
  miteruby_stored_stack_t *stack = (miteruby_stored_stack_t *)(stack_dedup_state.unique_stacks_array + next_stack_id.offset);
  stack->frame_count = frame_count;

  return (miteruby_stack_dedup_result_t) {.ok = {.id = next_stack_id, .reserved = true, .stack = miteruby_stack_dedup_get(next_stack_id)}};
}

bool miteruby_stack_dedup_commit(miteruby_stack_dedup_id_t stack_id, miteruby_stack_hash_t stack_hash) {
  verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_get_or_insert(&stack_dedup_state.unique_stacks, stack_hash, stack_id);
  if (verstable_unique_stacks_map_is_end(entry)) return false;

  miteruby_stored_stack_t *stack = (miteruby_stored_stack_t *)(stack_dedup_state.unique_stacks_array + stack_id.offset);
  stack_dedup_state.unique_stacks_pos += stored_stack_size(stack->frame_count);
  return true;
}
