#include "ddtrace.h"
#include "gc.h"

// Needs to be at least 5ms between GCs for us to treat them as separate events.
#define GC_NSEC_THRESHOLD (5 * 1000 * 1000)

#define NSEC_PER_SEC (1000 * 1000 * 1000)

#define UNUSED(x) (void)(x)

static int gc_hooked = false;

static struct timespec gc_enter_time;
// Ensure it's properly zero-initialized because we're going to check if it's
// non-zero in `datadog_gc_enter`.
static struct timespec gc_exit_time = {
  .tv_sec = 0,
  .tv_nsec = 0,
};

hrtime_t
timespec2hrtime(const struct timespec *ts)
{
  hrtime_t s = (hrtime_t)ts->tv_sec * NSEC_PER_SEC;
  hrtime_t ns = (hrtime_t)ts->tv_nsec;
  return s + ns;
}

void
gc_hook_once()
{
  // Don't add the GC hooks more than once.
  if (gc_hooked) {
    return;
  }

  rb_add_event_hook(gc_enter, RUBY_INTERNAL_EVENT_GC_ENTER, Qnil);
  rb_add_event_hook(gc_exit, RUBY_INTERNAL_EVENT_GC_EXIT, Qnil);
  gc_hooked = true;
}

void
gc_enter(rb_event_flag_t flag, VALUE data, VALUE self, ID mid, VALUE klass)
{
  UNUSED(flag);
  UNUSED(data);
  UNUSED(self);
  UNUSED(mid);
  UNUSED(klass);

  struct timespec tsnow;
  rb_timespec_now(&tsnow);

  if ((&gc_exit_time)->tv_sec > 0) {
    hrtime_t exit = timespec2hrtime(&gc_exit_time);
    hrtime_t now = timespec2hrtime(&tsnow);

    // Because Ruby calls its GC hooks *a lot* we have to establish a threshold
    // below which we'll count all individual GCs as one GC. This means that we
    // actually have to wait until we start the next GC before we can determine
    // if we've met the threshold for the previous GCs (or else this current GC
    // should be counted with the previous).
    if ((now - exit) > GC_NSEC_THRESHOLD) {
      ddtrace_postpone_report_gc_trace(&gc_enter_time, &gc_exit_time);
    } else {
      // Threshold not met, keep waiting.
      return;
    }
  }

  // Reset the entry timer since we're in a new GC.
  memcpy(&gc_enter_time, &tsnow, sizeof(struct timespec));
}

void
gc_exit(rb_event_flag_t flag, VALUE data, VALUE self, ID mid, VALUE klass)
{
  UNUSED(flag);
  UNUSED(data);
  UNUSED(self);
  UNUSED(mid);
  UNUSED(klass);

  rb_timespec_now(&gc_exit_time);
}
