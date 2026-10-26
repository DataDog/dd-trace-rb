#include "consumer_stack_dedup.h"
#include "allocator.h"

#include <stdlib.h>
#include <string.h>

#define UNIQUE_STACKS_ARRAY_CHUNK_SIZE (1024U * 1024U)

typedef struct {
  uint64_t hash;
  struct {
    union {
      const miteruby_event_frame_refs_t *refs;
      size_t offset;
    } as;
  } location;
  uint16_t frame_count;
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

static verstable_unique_stacks_map unique_stacks;
static char *unique_stacks_array = NULL;
static size_t unique_stacks_pos = 0;
static size_t unique_stacks_size = 0;
static size_t unique_stacks_map_allocated_bytes = 0;

static size_t stack_data_size(uint16_t frame_count) {
  return frame_count * (sizeof(miteruby_event_frame_refs_t) + sizeof(miteruby_event_frame_position_t));
}

static const miteruby_event_frame_refs_t *stack_key_refs(stack_key key) {
  return key.borrowed ? key.location.as.refs : ((const miteruby_stack_t *)(unique_stacks_array + key.location.as.offset))->refs;
}

static uint64_t stack_key_hash(stack_key key) {
  return key.hash;
}

static bool stack_key_equal(stack_key left, stack_key right) {
  return left.hash == right.hash && left.frame_count == right.frame_count &&
    memcmp(stack_key_refs(left), stack_key_refs(right), stack_data_size(left.frame_count)) == 0;
}

static void *unique_stacks_calloc(size_t size) {
  void *allocation = miteruby_allocator_alloc(size, "unique_stacks_map");
  if (allocation != NULL) unique_stacks_map_allocated_bytes += size;
  return allocation;
}

static void unique_stacks_free(void *allocation, size_t size) {
  miteruby_allocator_free(allocation, size);
  unique_stacks_map_allocated_bytes -= size;
}

void miteruby_consumer_stack_dedup_init(void) {
  verstable_unique_stacks_map_init(&unique_stacks);
}

void miteruby_consumer_stack_dedup_reset(void) {
  verstable_unique_stacks_map_clear(&unique_stacks);
  free(unique_stacks_array);
  unique_stacks_array = NULL;
  unique_stacks_pos = 0;
  unique_stacks_size = 0;
}

size_t miteruby_consumer_stack_dedup_size(void) {
  return sizeof(unique_stacks) + unique_stacks_size + unique_stacks_map_allocated_bytes;
}

const miteruby_stack_t *miteruby_consumer_stack_dedup_get(size_t stack_id) {
  return (const miteruby_stack_t *)(unique_stacks_array + stack_id);
}

static size_t deduplicate_stack(stack_key key, bool *inserted) {
  size_t previous_count = verstable_unique_stacks_map_size(&unique_stacks);
  verstable_unique_stacks_map_itr entry = verstable_unique_stacks_map_get_or_insert(&unique_stacks, key, unique_stacks_pos);
  if (verstable_unique_stacks_map_is_end(entry)) rb_bug("Failed to grow miteruby unique stacks map");
  *inserted = verstable_unique_stacks_map_size(&unique_stacks) != previous_count;
  if (!*inserted) return entry.data->val;

  size_t data_size = stack_data_size(key.frame_count);
  size_t record_size = (sizeof(miteruby_stack_t) + data_size + 7) & ~(size_t) 7;
  while (unique_stacks_size - unique_stacks_pos < record_size) {
    if (unique_stacks_size > SIZE_MAX - UNIQUE_STACKS_ARRAY_CHUNK_SIZE) rb_bug("Miteruby unique stacks array size overflow");
    size_t new_size = unique_stacks_size + UNIQUE_STACKS_ARRAY_CHUNK_SIZE;
    char *new_array = realloc(unique_stacks_array, new_size);
    if (new_array == NULL) rb_bug("Failed to grow miteruby unique stacks array");
    unique_stacks_array = new_array;
    unique_stacks_size = new_size;
  }

  miteruby_stack_t *stack = (miteruby_stack_t *)(unique_stacks_array + unique_stacks_pos);
  stack->frame_count = key.frame_count;
  memcpy(stack->refs, key.location.as.refs, data_size);
  // Preserve the key's hash and contents; offsets survive array growth without updating existing entries.
  entry.data->key.location.as.offset = unique_stacks_pos;
  entry.data->key.borrowed = false;
  unique_stacks_pos += record_size;
  return entry.data->val;
}

size_t miteruby_consumer_stack_dedup_get_or_insert(
  const miteruby_event_frame_refs_t *refs,
  uint16_t frame_count,
  bool *inserted
) {
  stack_key key = {
    .hash = vt_wyhash(refs, stack_data_size(frame_count)),
    .location.as.refs = refs,
    .frame_count = frame_count,
    .borrowed = true,
  };
  return deduplicate_stack(key, inserted);
}
