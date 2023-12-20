#pragma once

#include <datadog/profiling.h>
#include <ruby.h>

// A heap recorder keeps track of a collection of live heap objects.
//
// All allocations observed by this recorder for which a corresponding free was
// not yet observed are deemed as alive and can be iterated on to produce a
// live heap profile.
//
// NOTE: All public APIs of heap_recorder support receiving a NULL heap_recorder
//       in which case the behaviour will be a noop.
//
// WARN: Unless otherwise stated the heap recorder APIs assume calls are done
// under the GVL.
typedef struct heap_recorder heap_recorder;

// Extra data associated with each live object being tracked.
typedef struct live_object_data {
  // The weight of this object from a sampling perspective.
  //
  // A notion of weight is preserved for each tracked object to allow for an approximate
  // extrapolation to an unsampled view.
  //
  // Example: If we were sampling every 50 objects, then each sampled object
  //          could be seen as being representative of 50 objects.
  unsigned int weight;
} live_object_data;

// Data that is made available to iterators of heap recorder data for each live object
// tracked therein.
typedef struct {
  ddog_prof_Slice_Location locations;
  live_object_data object_data;
} heap_recorder_iteration_data;

// Initialize a new heap recorder.
heap_recorder* heap_recorder_new(void);

// Free a previously initialized heap recorder.
void heap_recorder_free(heap_recorder *heap_recorder);

// Do any cleanup needed after forking.
// WARN: Assumes this gets called before profiler is reinitialized on the fork
void heap_recorder_after_fork(heap_recorder *heap_recorder);

// Start a heap allocation recording on the heap recorder for a new object.
//
// This heap allocation recording needs to be ended via ::end_heap_allocation_recording
// before it will become fully committed and able to be iterated on.
//
// @param new_obj
//   The newly allocated Ruby object/value.
// @param weight
//   The sampling weight of this object.
//
// WARN: It needs to be paired with a ::end_heap_allocation_recording call.
void start_heap_allocation_recording(heap_recorder *heap_recorder, VALUE new_obj, unsigned int weight);

// End a previously started heap allocation recording on the heap recorder.
//
// It is at this point that an allocated object will become fully tracked and able to be iterated on.
//
// @param locations The stacktrace representing the location of the allocation.
//
// WARN: It is illegal to call this without previously having called ::start_heap_allocation_recording.
void end_heap_allocation_recording(heap_recorder *heap_recorder, ddog_prof_Slice_Location locations);

// Update the heap recorder to reflect the latest state of the VM and prepare internal structures
// for efficient iteration.
//
// WARN: This must be called strictly before iteration. Failing to do so will result in exceptions.
void heap_recorder_prepare_iteration(heap_recorder *heap_recorder);

// Optimize the heap recorder by cleaning up any data that might have been prepared specifically
// for the purpose of iterating over the heap recorder data.
//
// WARN: This must be called strictly after iteration to ensure proper cleanup and to keep the memory
// profile of the heap recorder low.
void heap_recorder_finish_iteration(heap_recorder *heap_recorder);

// Iterate over each live object being tracked by the heap recorder.
//
// NOTE: Iteration can be called without holding the Ruby Global VM lock.
// WARN: This must be called strictly after heap_recorder_prepare_iteration and before
// heap_recorder_finish_iteration.
//
// @param for_each_callback
//   A callback function that shall be called for each live object being tracked
//   by the heap recorder. Alongside the iteration_data for each live object,
//   a second argument will be forwarded with the contents of the optional
//   for_each_callback_extra_arg. Iteration will continue until the callback
//   returns false or we run out of objects.
// @param for_each_callback_extra_arg
//   Optional (NULL if empty) extra data that should be passed to the
//   callback function alongside the data for each live tracked object.
// @return true if iteration ran, false if something prevented it from running.
bool heap_recorder_for_each_live_object(
    heap_recorder *heap_recorder,
    bool (*for_each_callback)(heap_recorder_iteration_data data, void* extra_arg),
    void *for_each_callback_extra_arg);

// v--- TEST-ONLY APIs ---v

// Assert internal hashing logic is valid for the provided locations and its
// corresponding internal representations in heap recorder.
void heap_recorder_testonly_assert_hash_matches(ddog_prof_Slice_Location locations);

void heap_recorder_testonly_debug(heap_recorder *heap_recorder);
