#include <ruby.h>

#include "raw_events_queue_marking.h"
#include "../setup_signal_handler.h"
#include "event.h"

static void miteruby_raw_events_queue_mark_event(const uint64_t *data) {
  const miteruby_event_stack_sample_t *event = (const miteruby_event_stack_sample_t *)data;

  rb_gc_mark(event->thread.value);

  // Each frame is a contiguous pair of VALUE-sized CME/ISEQ references without padding (asserted in event.h),
  // so rb_gc_mark_locations can scan the whole frames array.
  rb_gc_mark_locations((const VALUE *)event->frames, (const VALUE *)&event->frames[event->header.frame_count]);
}

void miteruby_raw_events_queue_mark(miteruby_raw_events_queue_t *raw_events_queue) {
  // NOTE: ObjectSpace can also invoke dmark outside GC, where the signal handler would otherwise try to take our lock.
  //       Hence we mask out the signal as well during marking, even though the signal handler shouldn't try to push
  //       on the queue in the middle of GC.
  miteruby_raw_events_queue_visit(raw_events_queue, miteruby_raw_events_queue_mark_event, sigprof_signal_mask);
}
