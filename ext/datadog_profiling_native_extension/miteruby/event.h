#pragma once

#include <stddef.h>
#include <stdint.h>

// See design/EventDesign.md for field semantics and storage requirements.
typedef struct {
  VALUE value;
} value_thread_t;

typedef struct {
  // Cumulative thread CPU time in nanoseconds, or -1 when unavailable.
  long ns;
} cpu_time_t;

#define INVALID_CPU_TIME ((cpu_time_t) {.ns = -1})

typedef struct {
  // Monotonic observation time in nanoseconds.
  long ns;
} monotonic_time_t;

typedef enum __attribute__((packed)) {
  MITERUBY_EVENT_INVALID = 0,
  MITERUBY_EVENT_STACK_SAMPLE = 1,
  MITERUBY_EVENT_OVERFLOW = 2,
} miteruby_event_type_t;

enum {
  MITERUBY_EVENT_STACK_COMPLETE = 0,
  MITERUBY_EVENT_STACK_TRUNCATED = 1,
  MITERUBY_EVENT_STACK_UNAVAILABLE = 2,
  MITERUBY_EVENT_STACK_STATUS_MASK = 0x03,
  MITERUBY_EVENT_FROM_SIGNAL_HANDLER = 1 << 2,
};

typedef struct {
  uint16_t size_bytes;
  uint16_t frame_count;
  miteruby_event_type_t type;
  uint8_t flags;
  monotonic_time_t timestamp;
  cpu_time_t cpu_time;
} miteruby_event_header_t;

// See design/EventDesign.md for more details on why we store both cme and iseq.
typedef struct {
  const rb_callable_method_entry_t *cme;
  const rb_iseq_t *iseq;
} miteruby_event_frame_refs_t;

typedef struct {
  uint16_t value;
} miteruby_event_frame_position_t;

typedef struct {
  miteruby_event_header_t header;
  value_thread_t thread;
  miteruby_event_frame_refs_t refs[];
} miteruby_event_stack_sample_t;

typedef struct {
  miteruby_event_frame_refs_t *refs;
  miteruby_event_frame_position_t *positions;
  uint16_t frame_count;
} miteruby_event_stack_sample_view_t;

typedef struct {
  miteruby_event_header_t header;
} miteruby_event_overflow_t;

_Static_assert(sizeof(value_thread_t) == 8, "value_thread_t must be 8 bytes");
_Static_assert(sizeof(cpu_time_t) == 8, "cpu_time_t must be 8 bytes");
_Static_assert(sizeof(monotonic_time_t) == 8, "monotonic_time_t must be 8 bytes");
_Static_assert(sizeof(miteruby_event_type_t) == 1, "miteruby_event_type_t must be 1 byte");
_Static_assert(sizeof(miteruby_event_header_t) == 24, "miteruby_event_header_t must be 24 bytes");
_Static_assert(sizeof(miteruby_event_frame_refs_t) == 16, "miteruby_event_frame_refs_t must be 16 bytes");
_Static_assert(sizeof(miteruby_event_frame_position_t) == 2, "miteruby_event_frame_position_t must be 2 bytes");
_Static_assert(
  sizeof(miteruby_event_stack_sample_t) == 32 && offsetof(miteruby_event_stack_sample_t, refs) == 32,
  "miteruby_event_stack_sample_t frames must start after a 32-byte prefix"
);
_Static_assert(sizeof(miteruby_event_overflow_t) == 24, "miteruby_event_overflow_t must be 24 bytes");
