#pragma once

#include <datadog/profiling.h>
#include <ruby.h>

// A heap recorder keeps track of a collection of live heap objects.
//
// All allocations observed by this recorder for which a corresponding free was
// not yet observed are deemed as alive and can be iterated on to produce a
// live heap profile.
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

// Record a heap free on the heap recorder.
//
// Contrary to heap allocations, no sampling should be applied to frees. Missing a free event
// risks negatively effecting the accuracy of the live state of tracked objects and thus the accuracy
// of the resulting profiles.
//
// Two things can happen depending on the object:
// * The object isn't being tracked: the operation is a no-op.
// * The object is being tracked: it is marked as no longer alive and will not appear in the next
//   iteration.
//
// @param obj The object that was freed.
//
// NOTE: This function is safe to be called during a Ruby GC as it guarantees no heap mutations
//       during its execution.
void record_heap_free(heap_recorder *heap_recorder, VALUE obj);

// Flush any intermediate state that might be queued inside the heap recorder.
//
// NOTE: This should usually be called before iteration to ensure data is as little stale as possible.
void heap_recorder_flush(heap_recorder *heap_recorder);

// Iterate over each live object being tracked by the heap recorder.
//
// @param for_each_callback
//   A callback function that shall be called for each live object being tracked
//   by the heap recorder. Alongside the iteration_data for each live object,
//   a second argument will be forwarded with the contents of the optional
//   for_each_callback_extra_arg.
// @param for_each_callback_extra_arg
//   Optional (NULL if empty) extra data that should be passed to the
//   callback function alongside the data for each live tracked object.
//
// NOTE: This function is designed to be called from restricted scopes (e.g. without GVL) and, as such,
//       guarantees no heap mutations or raises.
void heap_recorder_for_each_live_object(
    heap_recorder *heap_recorder,
    void (*for_each_callback)(heap_recorder_iteration_data data, void* extra_arg),
    void *for_each_callback_extra_arg);
