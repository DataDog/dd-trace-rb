#pragma once

#include <ruby.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "consumer.h"

typedef enum {
  MITERUBY_SERIALIZER_OK = 0,
  MITERUBY_SERIALIZER_NOT_COMPLETED,
  MITERUBY_SERIALIZER_ALREADY_WORKING,
  MITERUBY_SERIALIZER_COMPRESSED_BUFFER_FULL,
  MITERUBY_SERIALIZER_COMPRESSION_ERROR,
  MITERUBY_SERIALIZER_COMPRESSION_INIT_ERROR,
  MITERUBY_SERIALIZER_COMPRESSION_CONTEXT_INIT_ERROR,
  MITERUBY_SERIALIZER_THREAD_CONTEXTS_FULL,
  MITERUBY_SERIALIZER_THREAD_CONTEXT_MISSING,
  MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK,
  MITERUBY_SERIALIZER_STRING_TABLE_ENCODING_ERROR,
  MITERUBY_SERIALIZER_LOCATION_ENCODING_ERROR,
  MITERUBY_SERIALIZER_SAMPLE_TYPE_ENCODING_ERROR,
  MITERUBY_SERIALIZER_FUNCTION_ENCODING_ERROR,
  MITERUBY_SERIALIZER_PROFILE_ENCODING_ERROR,
  MITERUBY_SERIALIZER_SAMPLE_SIZING_ERROR,
  MITERUBY_SERIALIZER_SAMPLE_ENCODING_ERROR,
  MITERUBY_SERIALIZER_VIREL_BUFFER_FULL,
  MITERUBY_SERIALIZER_INVALID_EVENT,
  MITERUBY_SERIALIZER_ALLOCATION_FAILED,
} miteruby_serializer_exit_reason_t;

typedef struct {
  void (*check_available)(VALUE);
  miteruby_serializer_exit_reason_t (*prepare)(
    VALUE, uint8_t *, size_t, const miteruby_mark_frame_array_t *, const miteruby_location_array_t *,
    const verstable_mark_threads_set *
  );
  miteruby_serializer_exit_reason_t (*serialize_no_gvl)(VALUE);
} miteruby_serializer_backend_t;

void miteruby_consumer_prepare_serialize_with_backend(VALUE serializer, const miteruby_serializer_backend_t *backend);

void miteruby_serializer_init(VALUE profiling_module);
void miteruby_serializer_check_available(VALUE serializer);
miteruby_serializer_exit_reason_t miteruby_serializer_prepare_serialize(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  const miteruby_mark_frame_array_t *frame_array, const miteruby_location_array_t *location_array,
  // TODO: Figure out better way to avoid passing in set
  const verstable_mark_threads_set *threads_set
);
// Called with the GVL after successful preparation and after releasing the consumer mutex.
miteruby_serializer_exit_reason_t miteruby_serializer_serialize_no_gvl(VALUE serializer);
void miteruby_serializer_raise_if_failed(miteruby_serializer_exit_reason_t reason);
