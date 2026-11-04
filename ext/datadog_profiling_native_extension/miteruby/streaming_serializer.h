#pragma once

#include <ruby.h>
#include <stddef.h>
#include <stdint.h>

#include "cme_iseq_map.h"

void miteruby_streaming_serializer_init(VALUE profiling_module);
// Caller holds the main ractor's GVL and consumer mutex; queue and map are borrowed for this call.
void miteruby_streaming_serializer_prepare_serialize(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  const verstable_mark_cme_iseq_map *mark_cme_iseq_map
);
