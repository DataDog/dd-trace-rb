#pragma once

#include <ruby.h>

#include "../private_vm_api_access.h"
#include "event.h"
#include "stack_dedup.h"

void miteruby_streaming_serializer_init(VALUE profiling_module);
void miteruby_streaming_serializer_record_stack_sample(
  VALUE serializer, const miteruby_event_deduped_sample_t *event, miteruby_stack_t stack
);
