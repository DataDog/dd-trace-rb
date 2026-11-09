#pragma once

#include <ruby.h>
#include <stddef.h>
#include <stdint.h>
#include "consumer.h"

typedef enum {
  MITERUBY_SERIALIZER_OK = 0,
  MITERUBY_SERIALIZER_COMPRESSED_BUFFER_FULL,
  MITERUBY_SERIALIZER_COMPRESSION_ERROR,
  MITERUBY_SERIALIZER_COMPRESSION_INIT_ERROR,
  MITERUBY_SERIALIZER_THREAD_CONTEXTS_FULL,
  MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK,
  MITERUBY_SERIALIZER_STRING_TABLE_ENCODING_ERROR,
  MITERUBY_SERIALIZER_LOCATION_ENCODING_ERROR,
  MITERUBY_SERIALIZER_SAMPLE_TYPE_ENCODING_ERROR,
  MITERUBY_SERIALIZER_FUNCTION_ENCODING_ERROR,
  MITERUBY_SERIALIZER_PROFILE_ENCODING_ERROR,
  MITERUBY_SERIALIZER_SAMPLE_SIZING_ERROR,
  MITERUBY_SERIALIZER_SAMPLE_ENCODING_ERROR,
} miteruby_serializer_exit_reason_t;

void miteruby_streaming_serializer_init(VALUE profiling_module);
miteruby_serializer_exit_reason_t miteruby_streaming_serializer_prepare_serialize(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  const miteruby_mark_cme_iseq_array_t *cme_iseq_array, const miteruby_location_array_t *location_array,
  // TODO: Figure out better way to avoid passing in set
  const verstable_mark_threads_set *threads_set
);
void miteruby_streaming_serializer_raise_if_failed(miteruby_serializer_exit_reason_t reason);
