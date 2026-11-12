#pragma once

#include "serializer.h"

void miteruby_virel_serializer_init(VALUE profiling_module);
void miteruby_virel_serializer_check_available(VALUE serializer);
miteruby_serializer_exit_reason_t miteruby_virel_serializer_prepare_serialize(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  const miteruby_mark_frame_array_t *frame_array, const miteruby_location_array_t *location_array,
  const verstable_mark_threads_set *threads_set
);
miteruby_serializer_exit_reason_t miteruby_virel_serializer_serialize_no_gvl(VALUE serializer);
