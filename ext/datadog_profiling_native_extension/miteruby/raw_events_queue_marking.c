#include <ruby.h>

#include "raw_events_queue_marking.h"
#include "../private_vm_api_access.h"
#include "../setup_signal_handler.h"

_Static_assert(
  offsetof(miteruby_event_stack_sample_t, thread.value) + sizeof(VALUE) ==
    offsetof(miteruby_event_stack_sample_t, refs),
  "Bulk marking requires frame references immediately after thread.value"
);
_Static_assert(
  offsetof(miteruby_event_frame_refs_t, cme) == 0 &&
    offsetof(miteruby_event_frame_refs_t, iseq) == sizeof(VALUE) &&
    sizeof(miteruby_event_frame_refs_t) == 2 * sizeof(VALUE),
  "Bulk marking requires contiguous VALUE-sized frame references without padding"
);

static void miteruby_raw_events_queue_mark_event(const uint64_t *data) {
  const miteruby_event_stack_sample_t *event = (const miteruby_event_stack_sample_t *)data;
  if (event->header.type != MITERUBY_EVENT_STACK_SAMPLE) return;

  // Assumes thread.value and all frame references form contiguous VALUE-sized slots without padding.
  // The static assertions above make incompatible layout changes fail compilation.
  rb_gc_mark_locations(&event->thread.value, (const VALUE *)&event->refs[event->header.frame_count]);
}

void miteruby_raw_events_queue_mark(miteruby_raw_events_queue_t *raw_events_queue) {
  // NOTE: ObjectSpace can also invoke dmark outside GC, where the signal handler would otherwise try to take our lock.
  //       Hence we mask out the signal as well during marking, even though the signal handler shouldn't try to push
  //       on the queue in the middle of GC.
  miteruby_raw_events_queue_visit(raw_events_queue, miteruby_raw_events_queue_mark_event, sigprof_signal_mask);
}
