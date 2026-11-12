#pragma once

#include <ruby.h>

#include "../private_vm_api_access.h"
#include "event.h"

// Deduped stack storage for the miteruby consumer
//
// None of this code is thread-safe, caller is expected to take care of that

// When deduplicating stacks, we treat stacks with the same hash as identical.
//
// This allows us to save CPU and memory:
// * We store delta-encoded location IDs, saving memory.
// * Converting every incoming stack to those indexes requires O(frames) lookups in the CME/ISEQ and location maps.
//   Hash-only identity avoids those lookups for already-seen stacks; new stacks still need conversion.
//   Hashing itself remains O(frames).
//
// Rapidhash V3's collision study reports results close to the ideal 64-bit model:
// https://github.com/Nicoshev/rapidhash/tree/rapidhash_v3#collision-based-hash-quality-study
// Using that model, P(any collision) ~= n*(n-1)/(2*2^64), or about 1 in 3.69 billion for
// 100,000 distinct stacks between serializations. This is an estimate, not a measured bound for our stack inputs.
// (We use rapidhash and not verstable's wyhash here as it's expected to both be better performing and have fewer collisions)
//
// A collision assigns samples of the later stack to the first stack with that hash,
// including subsequent occurrences until serialization or reset.
//
// Design note: If we're worried about collisions, we can use more bits for hash (see for instance
// https://www.mckusick.com/bookrefs/zfs_dedup.html on how zfs uses sha256 to dedup on-disk storage)
typedef struct {
  uint64_t hash;
} miteruby_stack_hash_t;

typedef struct {
  uint16_t frame_count;
  uint8_t *ids;
  const uint8_t *end;
} miteruby_stack_t;

typedef struct {
  bool error_storage_full;

  // Valid only when error_storage_full is false; an ID with offset zero is a successful result.
  struct {
    miteruby_stack_dedup_id_t id;
    bool reserved;
    // Empty for an existing stack. A reservation borrows worst-case storage until the next reservation or reset.
    miteruby_stack_t stack;
  } ok;
} miteruby_stack_dedup_result_t;

void miteruby_stack_dedup_init(void);
void miteruby_stack_dedup_reset(void);
size_t miteruby_stack_dedup_size(void);

typedef struct {
  size_t map_max_size_bytes;
  size_t map_entries;
} miteruby_stack_dedup_stats_t;

miteruby_stack_dedup_stats_t miteruby_stack_dedup_stats(void);

// Returned views borrow storage until the queue is drained or reset; callers must not modify stored stacks.
miteruby_stack_t miteruby_stack_dedup_get(uint8_t *events, miteruby_stack_dedup_id_t stack_id);
miteruby_stack_hash_t miteruby_stack_hash(const miteruby_event_stack_sample_t *event);
miteruby_stack_dedup_result_t miteruby_stack_dedup_get_or_reserve(
  uint16_t frame_count, miteruby_stack_hash_t stack_hash, uint8_t *events, size_t events_pos, size_t events_capacity
);

// Hold the consumer mutex from reservation through filling and commit. Commit only the latest reservation, once.
// Failure leaves the map and storage position unchanged; abandoned reservations need no cleanup.
// ids_end is the cursor after writing all frame IDs, within the reservation.
// Commit sets the sample size; the caller advances its queue position only after the whole sample succeeds.
bool miteruby_stack_dedup_commit(
  uint8_t *events, miteruby_stack_dedup_id_t stack_id, miteruby_stack_hash_t stack_hash, const uint8_t *ids_end
);
