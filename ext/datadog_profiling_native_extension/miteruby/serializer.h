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
} miteruby_serializer_exit_reason_t;

void miteruby_serializer_init(VALUE profiling_module);
void miteruby_serializer_check_available(VALUE serializer);
// Requires the GVL and consumer mutex. On success, takes ownership of the queue and empties the metadata arguments.
// Does not allocate Ruby objects or invoke Ruby callbacks during the transfer.
miteruby_serializer_exit_reason_t serializer_step1_serialize_with_gvl_with_consumer_lock(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  miteruby_mark_frame_array_t *frame_array, miteruby_location_array_t *location_array,
  verstable_mark_threads_set *threads_set
);
// Requires the GVL and an owned batch; the consumer mutex must be released.
miteruby_serializer_exit_reason_t serializer_step2_serialize_with_gvl_no_consumer_lock(VALUE serializer);
// Called with the GVL after successful preparation and after releasing the consumer mutex.
miteruby_serializer_exit_reason_t serializer_step3_serialize_no_gvl_no_consumer_lock(VALUE serializer);
void miteruby_serializer_raise_if_failed(miteruby_serializer_exit_reason_t reason);
