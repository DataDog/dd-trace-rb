#pragma once

#include <ruby.h>

#include "../private_vm_api_access.h"

// Except for startup initialization, callers hold dedupconsumer's consumed_events_mutex.
void miteruby_dedupconsumer_stack_dedup_init(void);
void miteruby_dedupconsumer_stack_dedup_reset(void);
size_t miteruby_dedupconsumer_stack_dedup_size(void);
const miteruby_stack_t *miteruby_dedupconsumer_stack_dedup_get(size_t stack_id);
size_t miteruby_dedupconsumer_stack_dedup_get_or_insert(
  const miteruby_event_frame_refs_t *refs,
  uint16_t frame_count,
  bool *inserted
);
