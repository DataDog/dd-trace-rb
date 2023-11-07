#pragma once

#include "stack_recorder.h"
#include <datadog/profiling.h>
#include <ruby.h>

typedef struct heap_recorder heap_recorder;

typedef struct {
  ddog_prof_Slice_Location locations;
  uint64_t inuse_objects;
} stack_iteration_data;

heap_recorder* heap_recorder_init(void);
void heap_recorder_free(heap_recorder *heap_recorder);
void heap_recorder_iterate_stacks(heap_recorder *heap_recorder, void (*for_each_callback)(stack_iteration_data stack_data, void* extra_arg), void *for_each_callback_extra_arg);
void start_heap_allocation_recording(heap_recorder *heap_recorder, VALUE new_obj, unsigned int weight, ddog_CharSlice *class_name);
void end_heap_allocation_recording(heap_recorder *heap_recorder, ddog_prof_Slice_Location locations);
void record_heap_free(heap_recorder *heap_recorder, VALUE obj);
