#pragma once

#include <ruby.h>
#include <stddef.h>
#include <stdint.h>
#include "consumer.h"
#include "../time_helpers.h"

void miteruby_streaming_serializer_init(VALUE profiling_module);
void miteruby_streaming_serializer_prepare_serialize(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  const miteruby_mark_cme_iseq_array_t *cme_iseq_array, const miteruby_location_array_t *location_array,
  // TODO: Figure out better way to avoid passing in set
  const verstable_mark_threads_set *threads_set, monotonic_to_system_epoch_state *time_converter
);
