#pragma once

#include <ruby.h>

#include "../private_vm_api_access.h"
#include "../time_helpers.h"

// Caller holds the main ractor's GVL and dedupconsumer's consumed_events_mutex.
void miteruby_dedupconsumer_recorder_init(void);
void miteruby_dedupconsumer_record_stack_sample(
  VALUE recorder_instance,
  const miteruby_event_stack_sample_t *event,
  monotonic_to_system_epoch_state *time_converter
);
