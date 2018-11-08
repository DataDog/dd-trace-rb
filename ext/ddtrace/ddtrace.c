#include <stdbool.h>
#include <ruby/ruby.h>
#include <ruby/debug.h>

#include "ddtrace.h"

static VALUE m_datadog;
static VALUE m_gc;

static ID id_call;
static ID id_ivHook;

static VALUE sym_start, sym_end;

// Avoid recursion hell: we don't want to report GC traces to Datadog *while*
// we're recording a GC trace in Datadog.
static int datadog_tracing = false;

static struct timespec gc_enter_time;
// Ensure it's properly zero-initialized because we're going to check if it's
// non-zero in `datadog_gc_enter`.
static struct timespec gc_exit_time = {
  .tv_sec = 0,
  .tv_nsec = 0,
};

#define UNUSED(x) (void)(x)

// Needs to be at least 5ms between GCs for us to treat them as separate events.
#define GC_NSEC_THRESHOLD (5 * 1000 * 1000)

#define NSEC_PER_SEC (1000 * 1000 * 1000)

hrtime_t
timespec2hrtime(const struct timespec *ts)
{
  hrtime_t s = (hrtime_t)ts->tv_sec * NSEC_PER_SEC;
  hrtime_t ns = (hrtime_t)ts->tv_nsec;
  return s + ns;
}

static void
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
      gc_trace_t *trace = malloc(sizeof(gc_trace_t));
      memcpy(&trace->start, &gc_enter_time, sizeof(struct timespec));
      memcpy(&trace->end, &gc_exit_time, sizeof(struct timespec));
      rb_postponed_job_register_one(0, (void (*)(void *))gc_report_trace, trace);
    } else {
      // Threshold not met, keep waiting.
      return;
    }
  }

  // Reset the entry timer since we're in a new GC.
  memcpy(&gc_enter_time, &tsnow, sizeof(struct timespec));
}

static void
gc_exit(rb_event_flag_t flag, VALUE data, VALUE self, ID mid, VALUE klass)
{
  UNUSED(flag);
  UNUSED(data);
  UNUSED(self);
  UNUSED(mid);
  UNUSED(klass);

  rb_timespec_now(&gc_exit_time);
}

static void
gc_report_trace(gc_trace_t *trace)
{
  VALUE start = rb_time_nano_new(trace->start.tv_sec, trace->start.tv_nsec);
  VALUE end = rb_time_nano_new(trace->end.tv_sec, trace->end.tv_nsec);
  free(trace);

  // Check that we have a hook to call.
  VALUE hook = rb_ivar_get(m_gc, id_ivHook);
  if (NIL_P(hook)) {
    return;
  }
  // Check that we're not already calling the hook.
  if (datadog_tracing) {
    return;
  }

  datadog_tracing = true;

  VALUE htrace = rb_hash_new();
  rb_hash_aset(htrace, sym_start, start);
  rb_hash_aset(htrace, sym_end, end);
  rb_funcall(hook, rb_intern("call"), 1, htrace);

  datadog_tracing = false;
}

VALUE
f_gc_set_hook(VALUE self, VALUE hook)
{
  rb_ivar_set(m_gc, id_ivHook, hook);
  return Qnil;
}

void
Init_ddtrace(void)
{
  id_call = rb_intern("call");
  id_ivHook = rb_intern("@hook");

  sym_start = ID2SYM(rb_intern("start"));
  sym_end = ID2SYM(rb_intern("end"));

  m_datadog = rb_const_get(rb_cObject, rb_intern("Datadog"));
  m_gc = rb_define_module_under(m_datadog, "NativeGC");
  rb_define_singleton_method(m_gc, "hook=", f_gc_set_hook, 1);

  rb_add_event_hook(gc_enter, RUBY_INTERNAL_EVENT_GC_ENTER, Qnil);
  rb_add_event_hook(gc_exit, RUBY_INTERNAL_EVENT_GC_EXIT, Qnil);
}
