#pragma once

#include <stddef.h>
#include <stdint.h>
#include "../collectors_stack.h"
#include "compressed_deltas.h"

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
  uint8_t flags;
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
} miteruby_frame_id_t;

typedef struct {
  uint20_t value;
} miteruby_location_id_t;

typedef struct {
  uint16_t value;
} miteruby_bytecode_pos_t;

typedef struct {
  miteruby_event_header_t header;
  value_thread_t thread;
  miteruby_frame_t frames[];
} miteruby_event_stack_sample_t;

#define MITERUBY_ROUND_UP_TO_8_BYTES(size_bytes) (((size_t) (size_bytes) + 7) & ~(size_t) 7)
#define MITERUBY_BYTES_PER_FRAME (sizeof(miteruby_frame_t) + sizeof(miteruby_bytecode_pos_t))
#define MITERUBY_MAX_SIZE_BYTES \
  MITERUBY_ROUND_UP_TO_8_BYTES(sizeof(miteruby_event_stack_sample_t) + MAX_FRAMES_LIMIT * MITERUBY_BYTES_PER_FRAME)

typedef struct {
  // Byte offset of the first sample with this stack in interned_events_queue; zero is valid. Invalidated on drain or reset.
  size_t offset;
} miteruby_stack_dedup_id_t;

typedef struct __attribute__((packed)) {
  uint16_t frame_count;
  uint16_t ids_size;
  uint8_t ids[];
} miteruby_stored_stack_t;

typedef struct {
  miteruby_event_header_t header;
  value_thread_t thread;
  miteruby_stack_dedup_id_t stack_id;
  miteruby_stored_stack_t stack;
} miteruby_event_deduped_sample_t;

_Static_assert(sizeof(value_thread_t) == 8, "value_thread_t must be 8 bytes");
_Static_assert(sizeof(cpu_time_t) == 8, "cpu_time_t must be 8 bytes");
_Static_assert(sizeof(monotonic_time_t) == 8, "monotonic_time_t must be 8 bytes");
_Static_assert(sizeof(miteruby_stack_dedup_id_t) == 8, "miteruby_stack_dedup_id_t must be 8 bytes");
_Static_assert(sizeof(miteruby_event_header_t) == 24, "miteruby_event_header_t must be 24 bytes");
_Static_assert(
  offsetof(miteruby_frame_t, cme) == 0 &&
    offsetof(miteruby_frame_t, iseq) == sizeof(VALUE) &&
    sizeof(miteruby_frame_t) == 2 * sizeof(VALUE),
  "Bulk marking requires contiguous VALUE-sized frame references without padding"
);
_Static_assert(sizeof(miteruby_frame_id_t) == 2, "miteruby_frame_id_t must be 2 bytes");
_Static_assert(sizeof(miteruby_location_id_t) == 4, "miteruby_location_id_t must be 4 bytes");
_Static_assert(sizeof(miteruby_bytecode_pos_t) == 2, "miteruby_bytecode_pos_t must be 2 bytes");
_Static_assert(sizeof(miteruby_event_stack_sample_t) == 32 && offsetof(miteruby_event_stack_sample_t, frames) == 32, "miteruby_event_stack_sample_t frames must start after a 32-byte prefix");
_Static_assert(offsetof(miteruby_stored_stack_t, ids) == 4, "miteruby_stored_stack_t IDs must start after a 4-byte prefix");
_Static_assert(offsetof(miteruby_event_deduped_sample_t, stack.ids) == 44, "miteruby_event_deduped_sample_t IDs must start after a 44-byte prefix");
_Static_assert(sizeof(miteruby_event_deduped_sample_t) == 48, "miteruby_event_deduped_sample_t must be 48 bytes");
