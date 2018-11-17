#include "ddtrace.h"
#include "gc.h"

static VALUE m_datadog, m_runtime, m_mri, m_gc;
static VALUE sym_start, sym_end;

static ID id_call;
static ID id_ivHook;

// Avoid recursion hell: we don't want to report GC traces to Datadog *while*
// we're recording a GC trace in Datadog.
static int ddtrace_gc_reporting = false;

void
ddtrace_postpone_report_gc_trace(const struct timespec *enter, const struct timespec *exit)
{
  ddtrace_gc_trace_t *trace = malloc(sizeof(ddtrace_gc_trace_t));
  memcpy(&trace->start, &enter, sizeof(struct timespec));
  memcpy(&trace->end, &exit, sizeof(struct timespec));
  rb_postponed_job_register_one(0, (void (*)(void *))ddtrace_report_gc_trace, trace);
}

void
ddtrace_report_gc_trace(ddtrace_gc_trace_t *trace)
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
  if (ddtrace_gc_reporting) {
    return;
  }

  ddtrace_gc_reporting = true;

  VALUE htrace = rb_hash_new();
  rb_hash_aset(htrace, sym_start, start);
  rb_hash_aset(htrace, sym_end, end);
  rb_funcall(hook, id_call, 1, htrace);

  ddtrace_gc_reporting = false;
}

VALUE
f_gc_set_hook(VALUE self, VALUE hook)
{
  rb_ivar_set(m_gc, id_ivHook, hook);
  gc_hook_once();
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
  m_runtime = rb_const_get(m_datadog, rb_intern("Runtime"));
  m_mri = rb_const_get(m_runtime, rb_intern("MRI"));
  m_gc = rb_define_module_under(m_mri, "GC");
  rb_define_singleton_method(m_gc, "hook=", f_gc_set_hook, 1);
}
