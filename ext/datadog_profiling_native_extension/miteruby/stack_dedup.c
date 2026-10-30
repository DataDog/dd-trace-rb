#include "stack_dedup.h"
#include "allocator.h"
#include "../datadog_ruby_common.h"
#include "../helpers.h"

#include <stdlib.h>
#include <string.h>

#define UNIQUE_STACKS_ARRAY_MAX_SIZE MiB_AS_BYTES(16)
#define UNIQUE_STACKS_SET_MAX_SIZE MiB_AS_BYTES(16)

typedef struct {
  uint16_t frame_count;
  miteruby_event_frame_refs_t refs[];
} miteruby_stack_t;

_Static_assert(offsetof(miteruby_stack_t, refs) == 8, "miteruby_stack_t frames must start after an 8-byte prefix");

typedef struct {
  uint64_t hash;
  struct {
    union {
      // Used at insertion time to point to input data
      const miteruby_event_stack_sample_view_t *view;

      miteruby_stack_dedup_id_t stack_id;
    } as;
  } location;

  bool view_borrowed; // if false, the union has a stack_id
} stack_key;

static uint64_t stack_key_hash(stack_key key);
static bool stack_key_equal(stack_key left, stack_key right);
static void *unique_stacks_calloc(size_t size);

#define NAME verstable_unique_stacks_set
#define KEY_TY stack_key
#define HASH_FN stack_key_hash
#define CMPR_FN stack_key_equal
#define MALLOC_FN unique_stacks_calloc
#define FREE_FN miteruby_allocator_free_sized
#include "verstable.h"

// Stack deduping design
//
// We keep two data structures:
//
// * `unique_stacks_array`: Contiguous storage of stacks in a very similar format as the sample event
// (Currently: frame_count, then CME, ISEQ for all frames and then the bytecode positions)
// Padding keeps each stack record and its CME/ISEQ pairs aligned to 8-byte boundaries.
//
// * `verstable_unique_stacks_set`: A set of stacks, with each stored key holding its hash and byte offset in `unique_stacks_array`.
//
// Here's how it looks as an example (each letter is a CME/ISEQ pair):
// * Input:
//   * Event 1: [A, B, C, D, 0, 1, 2, 3] (frame_count: 4)
//   * Event 2: [E, F, 0, 1] (frame_count: 2)
//   * Event 3: [A, B, C, D, 0, 1, 2, 3] (frame_count: 4)
//
// * Unique stacks array:
//   [ frame_count: 4 | padding | A | B | C | D | 0 | 1 | 2 | 3 | frame_count: 2 | padding | E | F | 0 | 1 | padding ]
//     ^                                                          ^
//     |                                                          |
//     Events 1 and 3                                             Event 2
//
// * Unique stacks set (view_borrowed = false):
//   [ hash(A B C D; 0 1 2 3) | offset:  0 ]  (Events 1 and 3)
//   [ hash(E F; 0 1)         | offset: 80 ]  (Event 2)
//
// Both of the above data structures are allocated with the miteruby allocator, since they're expected to be large and
// we want to manage them carefully.
//
// Even though conceptually CME and ISEQs are VALUEs that need marking for Ruby GC, the consumer tracks them separately
// in `verstable_objects_to_mark_set` so we don't need to mark them again here.

typedef struct {
  verstable_unique_stacks_set unique_stacks;

  uint8_t *unique_stacks_array;
  size_t unique_stacks_pos;
} miteruby_stack_dedup_state_t;

static miteruby_stack_dedup_state_t stack_dedup_state = {0};

static miteruby_event_stack_sample_view_t stack_key_view(stack_key key) {
  return key.view_borrowed ? *key.location.as.view : miteruby_stack_dedup_get(key.location.as.stack_id);
}

static uint64_t stack_view_hash(miteruby_event_stack_sample_view_t view) {
  if (view.frame_count == 0) return 0;

  uint64_t refs_hash = vt_wyhash(view.refs, view.frame_count * sizeof(*view.refs));
  uint64_t positions_hash = vt_wyhash(view.positions, view.frame_count * sizeof(*view.positions));
  return vt_wymix(refs_hash, positions_hash);
}

static uint64_t stack_key_hash(stack_key key) {
  return key.hash;
}

static bool stack_key_equal(stack_key left, stack_key right) {
  if (left.hash != right.hash) return false;

  miteruby_event_stack_sample_view_t left_view = stack_key_view(left);
  miteruby_event_stack_sample_view_t right_view = stack_key_view(right);

  if (left_view.frame_count != right_view.frame_count) return false;
  if (left_view.frame_count == 0) return true;

  return memcmp(left_view.refs, right_view.refs, left_view.frame_count * sizeof(*left_view.refs)) == 0 &&
    memcmp(left_view.positions, right_view.positions, left_view.frame_count * sizeof(*left_view.positions)) == 0;
}

static void *unique_stacks_calloc(size_t size) {
  if (size > UNIQUE_STACKS_SET_MAX_SIZE) return NULL;

  return miteruby_allocator_alloc(size, "unique_stacks_set");
}

bool miteruby_stack_dedup_init(void) {
  verstable_unique_stacks_set_init(&stack_dedup_state.unique_stacks);
  return miteruby_stack_dedup_reset();
}

bool miteruby_stack_dedup_reset(void) {
  uint8_t *new_array = miteruby_allocator_alloc(UNIQUE_STACKS_ARRAY_MAX_SIZE, "unique_stacks_array");
  if (new_array == NULL) return false;

  verstable_unique_stacks_set_clear(&stack_dedup_state.unique_stacks);
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
    .set_max_size_bytes = UNIQUE_STACKS_SET_MAX_SIZE,
    .set_entries = verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks),
  };
}

miteruby_event_stack_sample_view_t miteruby_stack_dedup_get(miteruby_stack_dedup_id_t stack_id) {
  miteruby_stack_t *stack = (miteruby_stack_t *)(stack_dedup_state.unique_stacks_array + stack_id.offset);

  return (miteruby_event_stack_sample_view_t) {
    .refs = stack->refs,
    .positions = (miteruby_event_frame_position_t *)&stack->refs[stack->frame_count],
    .frame_count = stack->frame_count,
  };
}

miteruby_stack_dedup_result_t miteruby_stack_dedup_get_or_insert(miteruby_event_stack_sample_view_t view) {
  if (miteruby_allocator_alloc_size(stack_dedup_state.unique_stacks_array) - stack_dedup_state.unique_stacks_pos < MITERUBY_MAX_SIZE_BYTES) {
    return (miteruby_stack_dedup_result_t) {.error_storage_full = true};
  }

  verstable_unique_stacks_set_itr entry = verstable_unique_stacks_set_get_or_insert(
    &stack_dedup_state.unique_stacks,
    (stack_key) {
      .hash = stack_view_hash(view),
      .location.as.view = &view,
      .view_borrowed = true,
    }
  );
  if (verstable_unique_stacks_set_is_end(entry)) return (miteruby_stack_dedup_result_t) {.error_storage_full = true};

  if (!entry.data->key.view_borrowed) {
    return (miteruby_stack_dedup_result_t) {.ok = {.id = entry.data->key.location.as.stack_id, .inserted = false}};
  }

  size_t stack_size = sizeof(miteruby_stack_t) + view.frame_count * (sizeof(*view.refs) + sizeof(*view.positions));
  size_t aligned_stack_size = ((stack_size + 7) / 8) * 8;

  miteruby_stack_dedup_id_t next_stack_id = {.offset = stack_dedup_state.unique_stacks_pos};
  miteruby_stack_t *stack = (miteruby_stack_t *)(stack_dedup_state.unique_stacks_array + next_stack_id.offset);
  stack->frame_count = view.frame_count;

  if (view.frame_count > 0) {
    miteruby_event_stack_sample_view_t stored = miteruby_stack_dedup_get(next_stack_id);
    memcpy(stored.refs, view.refs, view.frame_count * sizeof(*stored.refs));
    memcpy(stored.positions, view.positions, view.frame_count * sizeof(*stored.positions));
  }

  // Switching to owned storage must preserve the key's hash and contents.
  entry.data->key.location.as.stack_id = next_stack_id;
  entry.data->key.view_borrowed = false;
  stack_dedup_state.unique_stacks_pos += aligned_stack_size;

  return (miteruby_stack_dedup_result_t) {.ok = {.id = next_stack_id, .inserted = true}};
}

// This weird thing currently exists because we:
// 1. Check if the stack exists, and store it
// 2. If it didn't exist, try to add every VALUE to `objects_to_mark_set` (caller)
// 3. In step 2 we might run out of space. So this allows us to back out of 1 if step 2 fails.
void miteruby_stack_dedup_rollback_insert(miteruby_stack_dedup_id_t stack_id) {
  verstable_unique_stacks_set_erase(&stack_dedup_state.unique_stacks, (stack_key) {
    .hash = stack_view_hash(miteruby_stack_dedup_get(stack_id)),
    .location.as.stack_id = stack_id,
    .view_borrowed = false,
  });
  stack_dedup_state.unique_stacks_pos = stack_id.offset;
}
