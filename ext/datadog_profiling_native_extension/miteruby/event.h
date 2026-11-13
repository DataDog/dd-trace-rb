#pragma once

#include <ruby.h>
#include <stddef.h>
#include <stdint.h>
#include "../private_vm_api_access.h"

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

typedef struct {
  uint16_t size_bytes;
  uint16_t frame_count;
  uint8_t stack_truncated : 1;
  monotonic_time_t timestamp;
  cpu_time_t cpu_time;
} miteruby_event_header_t;

// See design/EventDesign.md for more details on why we store both cme and iseq.
typedef struct {
  const rb_callable_method_entry_t *cme;
  const rb_iseq_t *iseq;
} miteruby_frame_t;

typedef struct {
  uint16_t value;
} miteruby_bytecode_pos_t;

typedef struct {
  miteruby_event_header_t header;
  value_thread_t thread;
  miteruby_frame_t frames[];
} miteruby_event_stack_sample_t;

#define MITERUBY_ROUND_UP_TO_8_BYTES(size_bytes) (((size_t) (size_bytes) + 7) & ~(size_t) 7)

_Static_assert(sizeof(value_thread_t) == 8, "value_thread_t must be 8 bytes");
_Static_assert(sizeof(cpu_time_t) == 8, "cpu_time_t must be 8 bytes");
_Static_assert(sizeof(monotonic_time_t) == 8, "monotonic_time_t must be 8 bytes");
_Static_assert(sizeof(miteruby_event_header_t) == 24, "miteruby_event_header_t must be 24 bytes");
_Static_assert(
  offsetof(miteruby_frame_t, cme) == 0 &&
    offsetof(miteruby_frame_t, iseq) == sizeof(VALUE) &&
    sizeof(miteruby_frame_t) == 2 * sizeof(VALUE),
  "Bulk marking requires contiguous VALUE-sized frame references without padding"
);
_Static_assert(sizeof(miteruby_bytecode_pos_t) == 2, "miteruby_bytecode_pos_t must be 2 bytes");
_Static_assert(sizeof(miteruby_event_stack_sample_t) == 32 && offsetof(miteruby_event_stack_sample_t, frames) == 32, "miteruby_event_stack_sample_t frames must start after a 32-byte prefix");
