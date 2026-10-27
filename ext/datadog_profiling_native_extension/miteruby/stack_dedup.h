#pragma once

#include <ruby.h>

#include "../private_vm_api_access.h"

// Deduped stack storage for the miteruby consumer

// Except for startup initialization, callers hold consumer's consumed_events_mutex.
void miteruby_stack_dedup_init(void);
void miteruby_stack_dedup_reset(void);
size_t miteruby_stack_dedup_size(void);
// Returned views borrow storage until the next insertion or reset; callers must not modify it.
miteruby_event_stack_sample_view_t miteruby_stack_dedup_get(miteruby_stack_dedup_id_t stack_id);
miteruby_stack_dedup_id_t miteruby_stack_dedup_get_or_insert(
  miteruby_event_stack_sample_view_t view,
  bool *inserted
);
