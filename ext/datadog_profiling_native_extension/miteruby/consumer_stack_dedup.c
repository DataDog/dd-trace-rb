#include "consumer_stack_dedup.h"
#include "allocator.h"

#include <stdlib.h>
#include <string.h>

#define UNIQUE_STACKS_ARRAY_CHUNK_SIZE (1024U * 1024U)

typedef struct {
  uint64_t hash;
  struct {
    union {
      // Used at insertion time to point to input data
      const miteruby_event_stack_sample_view_t *view;

      // Keys already in the map point to an offset directly (and can build a view from calling `miteruby_consumer_stack_dedup_get` with it)
      size_t offset;
    } as;
  } location;
  bool borrowed;
} stack_key;

static uint64_t stack_key_hash(stack_key key);
static bool stack_key_equal(stack_key left, stack_key right);
static void *unique_stacks_calloc(size_t size);
static void unique_stacks_free(void *allocation, size_t size);

#define NAME verstable_unique_stacks_map
#define KEY_TY stack_key
#define VAL_TY size_t
#define HASH_FN stack_key_hash
#define CMPR_FN stack_key_equal
#define MALLOC_FN unique_stacks_calloc
#define FREE_FN unique_stacks_free
#include "verstable.h"


typedef struct {
  verstable_unique_stacks_map unique_stacks;
  size_t unique_stacks_map_allocated_bytes;

  char *unique_stacks_array;
  size_t unique_stacks_pos;
  size_t unique_stacks_size;
} miteruby_stack_dedup_state_t;

static miteruby_stack_dedup_state_t stack_dedup_state = {0};

static size_t stack_data_size(uint16_t frame_count) {
  return frame_count * (sizeof(miteruby_event_frame_refs_t) + sizeof(miteruby_event_frame_position_t));
}

static miteruby_event_stack_sample_view_t stack_key_view(stack_key key) {
  return key.borrowed ? *key.location.as.view : miteruby_consumer_stack_dedup_get(key.location.as.offset);
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
  void *allocation = miteruby_allocator_alloc(size, "unique_stacks_map");
  if (allocation != NULL) stack_dedup_state.unique_stacks_map_allocated_bytes += size;
  return allocation;
}

static void unique_stacks_free(void *allocation, size_t size) {
  miteruby_allocator_free(allocation, size);
  stack_dedup_state.unique_stacks_map_allocated_bytes -= size;
}

void miteruby_consumer_stack_dedup_init(void) {
  verstable_unique_stacks_map_init(&stack_dedup_state.unique_stacks);
  miteruby_consumer_stack_dedup_reset();
}

void miteruby_consumer_stack_dedup_reset(void) {
  char *new_array = miteruby_allocator_alloc(UNIQUE_STACKS_ARRAY_CHUNK_SIZE, "unique_stacks_array");
  if (new_array == NULL) rb_bug("Failed to allocate miteruby unique stacks array");

  verstable_unique_stacks_map_clear(&stack_dedup_state.unique_stacks);
  miteruby_allocator_free(stack_dedup_state.unique_stacks_array, stack_dedup_state.unique_stacks_size);

  stack_dedup_state.unique_stacks_array = new_array;
  stack_dedup_state.unique_stacks_pos = 0;
  stack_dedup_state.unique_stacks_size = UNIQUE_STACKS_ARRAY_CHUNK_SIZE;
}

size_t miteruby_consumer_stack_dedup_size(void) {
  return sizeof(stack_dedup_state.unique_stacks) + stack_dedup_state.unique_stacks_size + stack_dedup_state.unique_stacks_map_allocated_bytes;
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
  size_t previous_count = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks);
  verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_get_or_insert(&stack_dedup_state.unique_stacks, key, stack_id);
  if (verstable_unique_stacks_map_is_end(entry)) rb_bug("Failed to grow miteruby unique stacks map");
  *inserted = verstable_unique_stacks_map_size(&stack_dedup_state.unique_stacks) != previous_count;
  if (!*inserted) return entry.data->val;

  miteruby_event_stack_sample_view_t view = stack_key_view(key);
  size_t data_size = stack_data_size(view.frame_count);
  size_t record_size = (sizeof(miteruby_stack_t) + data_size + 7) & ~(size_t) 7;
  while (stack_dedup_state.unique_stacks_size - stack_dedup_state.unique_stacks_pos < record_size) {
    if (stack_dedup_state.unique_stacks_size > SIZE_MAX - UNIQUE_STACKS_ARRAY_CHUNK_SIZE) rb_bug("Miteruby unique stacks array size overflow");
    size_t new_size = stack_dedup_state.unique_stacks_size + UNIQUE_STACKS_ARRAY_CHUNK_SIZE;
    char *new_array = miteruby_allocator_alloc(new_size, "unique_stacks_array");
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
  entry.data->key.borrowed = false;
  stack_dedup_state.unique_stacks_pos += record_size;
  return entry.data->val;
}

size_t miteruby_consumer_stack_dedup_get_or_insert(
  miteruby_event_stack_sample_view_t view,
  bool *inserted
) {
  stack_key key = {
    .hash = stack_view_hash(view),
    .location.as.view = &view,
    .borrowed = true,
  };
  return deduplicate_stack(key, inserted);
}
