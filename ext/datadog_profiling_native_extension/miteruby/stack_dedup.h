#pragma once

#include <ruby.h>

#include "../private_vm_api_access.h"

// Deduped stack storage for the miteruby consumer
//
// None of this code is thread-safe, caller is expected to take care of that

// When deduplicating stacks, we treat stacks with the same hash as identical.
//
// This allows us to save CPU and memory:
// * We plan to store ISEQ/CME pairs as `miteruby_cme_iseq_id_t` indexes, saving memory.
// * Converting every incoming stack to those indexes requires O(frames) lookups in `verstable_mark_cme_iseq_map`.
//   Hash-only identity avoids those lookups for already-seen stacks; new stacks still need conversion.
//   Hashing itself remains O(frames).
//
// Rapidhash V3's collision study reports results close to the ideal 64-bit model:
// https://github.com/Nicoshev/rapidhash/tree/rapidhash_v3#collision-based-hash-quality-study
// Using that model, P(any collision) ~= n*(n-1)/(2*2^64), or about 1 in 3.69 billion for
// 100,000 distinct stacks since reset. This is an estimate, not a measured bound for our stack inputs.
// (We use rapidhash and not verstable's wyhash here as it's expected to both be better performing and have fewer collisions)
//
// A collision assigns samples of the later stack to the first stack with that hash,
// including subsequent occurrences until reset.
//
// Design note: If we're worried about collisions, we can use more bits for hash (see for instance
// https://www.mckusick.com/bookrefs/zfs_dedup.html on how zfs uses sha256 to dedup on-disk storage)
typedef struct {
  uint64_t hash;
} miteruby_stack_hash_t;

typedef struct {
  bool error_storage_full;

  // Valid only when error_storage_full is false; an ID with offset zero is a successful result.
  struct {
    miteruby_stack_dedup_id_t id;
    bool inserted;
  } ok;
} miteruby_stack_dedup_result_t;

bool miteruby_stack_dedup_init(void);
bool miteruby_stack_dedup_reset(void);
size_t miteruby_stack_dedup_size(void);

typedef struct {
  size_t array_max_size_bytes;
  size_t array_used_size_bytes;
  size_t map_max_size_bytes;
  size_t map_entries;
} miteruby_stack_dedup_stats_t;

miteruby_stack_dedup_stats_t miteruby_stack_dedup_stats(void);

// Returned views borrow storage until the next reset; callers must not modify it.
miteruby_event_stack_sample_view_t miteruby_stack_dedup_get(miteruby_stack_dedup_id_t stack_id);
miteruby_stack_hash_t miteruby_stack_hash(const miteruby_event_stack_sample_t *event);
miteruby_stack_dedup_result_t miteruby_stack_dedup_get_or_insert(const miteruby_event_stack_sample_t *event, miteruby_stack_hash_t stack_hash);

// Only the latest newly inserted stack may be rolled back, before any sample references it.
void miteruby_stack_dedup_rollback_insert(miteruby_stack_dedup_id_t stack_id, miteruby_stack_hash_t stack_hash);
