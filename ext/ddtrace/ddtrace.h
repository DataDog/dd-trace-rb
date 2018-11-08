#ifndef DDTRACE_H
#define DDTRACE_H 1

// High-resolution time.
typedef uint64_t hrtime_t;

typedef struct gc_trace {
  struct timespec start;
  struct timespec end;
} gc_trace_t;

static void gc_report_trace(gc_trace_t *trace);

#endif /* DDTRACE_H */
