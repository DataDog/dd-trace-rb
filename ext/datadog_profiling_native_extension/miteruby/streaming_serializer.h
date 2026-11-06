#pragma once

#include <ruby.h>
#include <stddef.h>
#include <stdint.h>
#include "consumer.h"

void miteruby_streaming_serializer_init(VALUE profiling_module);
void miteruby_streaming_serializer_prepare_serialize(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  const miteruby_mark_cme_iseq_array_t *cme_iseq_array
);
