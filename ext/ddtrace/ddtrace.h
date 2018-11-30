#ifndef DDTRACE_H
#define DDTRACE_H 1

#include <stdbool.h>
#include <ruby/ruby.h>
#include <ruby/debug.h>

// High-resolution time.
typedef uint64_t hrtime_t;

typedef struct ddtrace_gc_trace {
  struct timespec start;
  struct timespec end;
} ddtrace_gc_trace_t;

void ddtrace_postpone_report_gc_trace(const struct timespec *enter, const struct timespec *exit);
void ddtrace_report_gc_trace(ddtrace_gc_trace_t *trace);

#endif /* DDTRACE_H */
