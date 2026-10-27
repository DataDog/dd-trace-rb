#include "consumer_stack_dedup.h"
#include "allocator.h"

#include <stdlib.h>
#include <string.h>

#define UNIQUE_STACKS_ARRAY_CHUNK_SIZE (1024U * 1024U)

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

      // Keys already in the set point to an offset directly (and can build a view from calling `miteruby_consumer_stack_dedup_get` with it)
      size_t offset;
    } as;
  } location;
  bool view_borrowed;
} stack_key;

static uint64_t stack_key_hash(stack_key key);
static bool stack_key_equal(stack_key left, stack_key right);
static void *unique_stacks_calloc(size_t size);
static void unique_stacks_free(void *allocation, size_t size);

#define NAME verstable_unique_stacks_set
#define KEY_TY stack_key
#define HASH_FN stack_key_hash
#define CMPR_FN stack_key_equal
#define MALLOC_FN unique_stacks_calloc
#define FREE_FN unique_stacks_free
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
  size_t unique_stacks_set_allocated_bytes;

  uint8_t *unique_stacks_array;
  size_t unique_stacks_pos;
  size_t unique_stacks_size;
} miteruby_stack_dedup_state_t;

static miteruby_stack_dedup_state_t stack_dedup_state = {0};

static size_t stack_data_size(uint16_t frame_count) {
  return frame_count * (sizeof(miteruby_event_frame_refs_t) + sizeof(miteruby_event_frame_position_t));
}

static miteruby_event_stack_sample_view_t stack_key_view(stack_key key) {
  return key.view_borrowed ? *key.location.as.view : miteruby_consumer_stack_dedup_get(key.location.as.offset);
}

static uint64_t stack_view_hash(miteruby_event_stack_sample_view_t view) {
  if (view.frame_count == 0) return 0;
  uint64_t refs_hash = vt_wyhash(view.refs, view.frame_count * sizeof(*view.refs));
  uint64_t positions_hash = vt_wyhash(view.positions, view.frame_count * sizeof(*view.positions));
  return vt_hash_integer(refs_hash) ^ positions_hash;
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
  void *allocation = miteruby_allocator_alloc(size, "unique_stacks_set");
  if (allocation != NULL) stack_dedup_state.unique_stacks_set_allocated_bytes += size;
  return allocation;
}

static void unique_stacks_free(void *allocation, size_t size) {
  miteruby_allocator_free(allocation, size);
  stack_dedup_state.unique_stacks_set_allocated_bytes -= size;
}

void miteruby_consumer_stack_dedup_init(void) {
  verstable_unique_stacks_set_init(&stack_dedup_state.unique_stacks);
  miteruby_consumer_stack_dedup_reset();
}

void miteruby_consumer_stack_dedup_reset(void) {
  uint8_t *new_array = miteruby_allocator_alloc(UNIQUE_STACKS_ARRAY_CHUNK_SIZE, "unique_stacks_array");
  if (new_array == NULL) rb_bug("Failed to allocate miteruby unique stacks array");

  verstable_unique_stacks_set_clear(&stack_dedup_state.unique_stacks);
  miteruby_allocator_free(stack_dedup_state.unique_stacks_array, stack_dedup_state.unique_stacks_size);

  stack_dedup_state.unique_stacks_array = new_array;
  stack_dedup_state.unique_stacks_pos = 0;
  stack_dedup_state.unique_stacks_size = UNIQUE_STACKS_ARRAY_CHUNK_SIZE;
}

size_t miteruby_consumer_stack_dedup_size(void) {
  return sizeof(stack_dedup_state.unique_stacks) + stack_dedup_state.unique_stacks_size + stack_dedup_state.unique_stacks_set_allocated_bytes;
}

miteruby_event_stack_sample_view_t miteruby_consumer_stack_dedup_get(size_t stack_id) {
  miteruby_stack_t *stack = (miteruby_stack_t *)(stack_dedup_state.unique_stacks_array + stack_id);
  return (miteruby_event_stack_sample_view_t) {
    .refs = stack->refs,
    .positions = (miteruby_event_frame_position_t *)&stack->refs[stack->frame_count],
    .frame_count = stack->frame_count,
  };
}

static size_t deduplicate_stack(stack_key key, bool *inserted) {
  size_t stack_id = stack_dedup_state.unique_stacks_pos;
  size_t previous_count = verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks);
  verstable_unique_stacks_set_itr entry = verstable_unique_stacks_set_get_or_insert(&stack_dedup_state.unique_stacks, key);
  if (verstable_unique_stacks_set_is_end(entry)) rb_bug("Failed to grow miteruby unique stacks set");
  *inserted = verstable_unique_stacks_set_size(&stack_dedup_state.unique_stacks) != previous_count;
  if (!*inserted) return entry.data->key.location.as.offset;

  miteruby_event_stack_sample_view_t view = stack_key_view(key);
  size_t data_size = stack_data_size(view.frame_count);
  size_t record_size = (sizeof(miteruby_stack_t) + data_size + 7) & ~(size_t) 7;
  while (stack_dedup_state.unique_stacks_size - stack_dedup_state.unique_stacks_pos < record_size) {
    if (stack_dedup_state.unique_stacks_size > SIZE_MAX - UNIQUE_STACKS_ARRAY_CHUNK_SIZE) rb_bug("Miteruby unique stacks array size overflow");
    size_t new_size = stack_dedup_state.unique_stacks_size + UNIQUE_STACKS_ARRAY_CHUNK_SIZE;
    uint8_t *new_array = miteruby_allocator_alloc(new_size, "unique_stacks_array");
    if (new_array == NULL) rb_bug("Failed to grow miteruby unique stacks array");
    memcpy(new_array, stack_dedup_state.unique_stacks_array, stack_dedup_state.unique_stacks_pos);
    miteruby_allocator_free(stack_dedup_state.unique_stacks_array, stack_dedup_state.unique_stacks_size);
    stack_dedup_state.unique_stacks_array = new_array;
    stack_dedup_state.unique_stacks_size = new_size;
  }

  miteruby_stack_t *stack = (miteruby_stack_t *)(stack_dedup_state.unique_stacks_array + stack_id);
  stack->frame_count = view.frame_count;
  if (view.frame_count > 0) {
    miteruby_event_stack_sample_view_t stored = miteruby_consumer_stack_dedup_get(stack_id);
    memcpy(stored.refs, view.refs, view.frame_count * sizeof(*stored.refs));
    memcpy(stored.positions, view.positions, view.frame_count * sizeof(*stored.positions));
  }
  // Preserve the key's hash and contents; offsets survive array growth without updating existing entries.
  entry.data->key.location.as.offset = stack_id;
  entry.data->key.view_borrowed = false;
  stack_dedup_state.unique_stacks_pos += record_size;
  return entry.data->key.location.as.offset;
}

size_t miteruby_consumer_stack_dedup_get_or_insert(miteruby_event_stack_sample_view_t view, bool *inserted) {
  return deduplicate_stack(
    (stack_key) {
      .hash = stack_view_hash(view),
      .location.as.view = &view,
      .view_borrowed = true,
    },
    inserted
  );
}
