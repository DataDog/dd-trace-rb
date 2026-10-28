#pragma once

#include <ruby.h>

#include "../private_vm_api_access.h"

// Deduped stack storage for the miteruby consumer
//
// None of this code is thread-safe, caller is expected to take care of that

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

// Returned views borrow storage until the next reset; callers must not modify it.
miteruby_event_stack_sample_view_t miteruby_stack_dedup_get(miteruby_stack_dedup_id_t stack_id);
miteruby_stack_dedup_result_t miteruby_stack_dedup_get_or_insert(miteruby_event_stack_sample_view_t view);

// Only the latest newly inserted stack may be rolled back, before any sample references it.
void miteruby_stack_dedup_rollback_insert(miteruby_stack_dedup_id_t stack_id);
