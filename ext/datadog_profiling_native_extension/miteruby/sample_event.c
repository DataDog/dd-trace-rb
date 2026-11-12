#include <ruby.h>

#include "sample_event.h"
#include "../private_vm_api_access.h"
#include "../time_helpers.h"

#include <errno.h>

static bool miteruby_sample_event_publish_internal(
  miteruby_raw_events_queue_t *raw_events_queue, value_thread_t thread, const sigset_t *signal_mask, cpu_time_t cpu_time, bool from_signal_handler
);
static cpu_time_t current_thread_cpu_time(void);
static inline monotonic_time_t monotonic_time_now(void);
static inline size_t round_up_to_8_bytes(size_t size_bytes);

bool miteruby_sample_event_publish_sighandler(miteruby_raw_events_queue_t *raw_events_queue) {
  int saved_errno = errno;
  bool published = miteruby_sample_event_publish_internal(
    raw_events_queue, (value_thread_t) {.value = rb_thread_current()}, NULL, current_thread_cpu_time(), true
  );
  errno = saved_errno;
  return published;
}

bool miteruby_sample_event_publish_mask(miteruby_raw_events_queue_t *raw_events_queue, const sigset_t *signal_mask) {
  return miteruby_sample_event_publish_internal(
    raw_events_queue, (value_thread_t) {.value = rb_thread_current()}, signal_mask, current_thread_cpu_time(), false
  );
}

bool miteruby_sample_event_publish_thread(miteruby_raw_events_queue_t *raw_events_queue, value_thread_t thread, const sigset_t *signal_mask) {
  return miteruby_sample_event_publish_internal(raw_events_queue, thread, signal_mask, INVALID_CPU_TIME, false);
}

bool miteruby_sample_event_publish_testing(miteruby_raw_events_queue_t *raw_events_queue, value_thread_t thread, const sigset_t *signal_mask, cpu_time_t cpu_time) {
  return miteruby_sample_event_publish_internal(raw_events_queue, thread, signal_mask, cpu_time, false);
}

static cpu_time_t current_thread_cpu_time(void) {
  struct timespec cpu_time;
  if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpu_time) != 0) return INVALID_CPU_TIME;
  return (cpu_time_t) {.ns = SECONDS_AS_NS(cpu_time.tv_sec) + cpu_time.tv_nsec};
}

static inline monotonic_time_t monotonic_time_now(void) {
  return (monotonic_time_t) {.ns = monotonic_wall_time_now_ns()};
}

// TODO: Revisit upstream rb_profile_frames if we accept its block/eval fidelity trade-off (see design/EventDesign.md),
// or an upstream API supplies the frame metadata and bytecode positions needed for deferred symbolication.
// TODO: Emit correlation data from tracing (trace id, span id, endpoint)
// TODO: We're allocating quite a lot on the stack, maybe we shouldn't
static bool miteruby_sample_event_publish_internal(
  miteruby_raw_events_queue_t *raw_events_queue, value_thread_t thread, const sigset_t *signal_mask, cpu_time_t cpu_time, bool from_signal_handler
) {
  monotonic_time_t timestamp = monotonic_time_now();
  frame_info frames[MAX_FRAMES_LIMIT + 1];
  int count = ddtrace_rb_profile_frames(thread.value, 0, MAX_FRAMES_LIMIT + 1, frames, true);

  union {
    miteruby_event_stack_sample_t event;
    uint64_t words[MITERUBY_MAX_SIZE_BYTES / sizeof(uint64_t)];
  } storage = {.words = {0}};
  miteruby_event_stack_sample_t *event = &storage.event;

  event->header.timestamp = timestamp;
  event->header.cpu_time = cpu_time;
  event->thread = thread;
  if (count <= 0) {
    event->header.flags = MITERUBY_EVENT_STACK_UNAVAILABLE;
    count = 0;
  } else if (count > MAX_FRAMES_LIMIT) {
    event->header.flags = MITERUBY_EVENT_STACK_TRUNCATED;
    count = MAX_FRAMES_LIMIT;
  } else {
    event->header.flags = MITERUBY_EVENT_STACK_COMPLETE;
  }
  if (from_signal_handler) event->header.flags |= MITERUBY_EVENT_FROM_SIGNAL_HANDLER;
  event->header.frame_count = count;

  miteruby_bytecode_pos_t *bytecode_positions = (miteruby_bytecode_pos_t *)&event->frames[count];
  for (uint16_t i = 0; i < count; i++) {
    event->frames[i] = (miteruby_frame_t) {
      .cme = frames[i].cme,
      .iseq = frames[i].is_ruby_frame ? frames[i].as.ruby_frame.iseq : NULL,
    };
    int bytecode_position = frames[i].is_ruby_frame ? frames[i].as.ruby_frame.line : 0;
    bytecode_positions[i].value =
      bytecode_position >= 0 && bytecode_position < UINT16_MAX ? (uint16_t) bytecode_position : UINT16_MAX;
  }
  size_t size_bytes = round_up_to_8_bytes(sizeof(*event) + count * MITERUBY_BYTES_PER_FRAME);
  event->header.size_bytes = size_bytes;

  return miteruby_raw_events_queue_try_write(raw_events_queue, storage.words, event->header.size_bytes / sizeof(uint64_t), signal_mask);
}

static inline size_t round_up_to_8_bytes(size_t size_bytes) {
  return (size_bytes + 7) & ~(size_t) 7;
}
