#pragma once

#include <ruby.h>

#include "../private_vm_api_access.h"
#include "../time_helpers.h"

// Caller holds the main ractor's GVL and consumer's consumed_events_mutex.
void miteruby_consumer_recorder_init(void);
void miteruby_consumer_record_stack_sample(
  VALUE recorder_instance,
  const miteruby_event_deduped_sample_t *event,
  const miteruby_event_frame_refs_t *refs,
  const miteruby_event_frame_position_t *positions,
  monotonic_to_system_epoch_state *time_converter
);
