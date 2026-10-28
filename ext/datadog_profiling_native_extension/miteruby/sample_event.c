#include <ruby.h>

#include "sample_event.h"
#include "../private_vm_api_access.h"
#include "../time_helpers.h"

#include <errno.h>
#include <string.h>

static bool miteruby_sample_event_publish_internal(
  miteruby_buffer_t *buffer, value_thread_t thread, const sigset_t *signal_mask, cpu_time_t cpu_time, bool from_signal_handler
);
static cpu_time_t current_thread_cpu_time(void);
static inline monotonic_time_t monotonic_time_now(void);
static inline size_t round_up_to_8_bytes(size_t size_bytes);

bool miteruby_sample_event_publish_sighandler(miteruby_buffer_t *buffer) {
  int saved_errno = errno;
  bool published = miteruby_sample_event_publish_internal(
    buffer, (value_thread_t) {.value = rb_thread_current()}, NULL, current_thread_cpu_time(), true
  );
  errno = saved_errno;
  return published;
}

bool miteruby_sample_event_publish_mask(miteruby_buffer_t *buffer, const sigset_t *signal_mask) {
  return miteruby_sample_event_publish_internal(
    buffer, (value_thread_t) {.value = rb_thread_current()}, signal_mask, current_thread_cpu_time(), false
  );
}

bool miteruby_sample_event_publish_thread(miteruby_buffer_t *buffer, value_thread_t thread, const sigset_t *signal_mask) {
  return miteruby_sample_event_publish_internal(buffer, thread, signal_mask, INVALID_CPU_TIME, false);
}

bool miteruby_sample_event_publish_testing(miteruby_buffer_t *buffer, value_thread_t thread, const sigset_t *signal_mask, cpu_time_t cpu_time) {
  return miteruby_sample_event_publish_internal(buffer, thread, signal_mask, cpu_time, false);
}

static cpu_time_t current_thread_cpu_time(void) {
  struct timespec cpu_time;
  if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpu_time) != 0) return INVALID_CPU_TIME;
  return (cpu_time_t) {.ns = SECONDS_AS_NS(cpu_time.tv_sec) + cpu_time.tv_nsec};
}

static inline monotonic_time_t monotonic_time_now(void) {
  return (monotonic_time_t) {.ns = monotonic_wall_time_now_ns()};
}

// TODO: Move away from hardcoded limit of 400 frames
// TODO: Consider finally moving to upstream rb_profile_frames
static bool miteruby_sample_event_publish_internal(
  miteruby_buffer_t *buffer, value_thread_t thread, const sigset_t *signal_mask, cpu_time_t cpu_time, bool from_signal_handler
) {
  union {
    miteruby_event_stack_sample_t event;
    uint64_t words[MITERUBY_MAX_SIZE_BYTES / sizeof(uint64_t)];
  } storage = {.words = {0}};
  miteruby_event_frame_position_t positions[MITERUBY_MAX_FRAMES];
  miteruby_event_stack_sample_t *event = &storage.event;
  miteruby_event_stack_sample_view_t view = {.refs = event->refs, .positions = positions};

  event->header.timestamp = monotonic_time_now();
  event->header.cpu_time = cpu_time;
  event->header.type = MITERUBY_EVENT_STACK_SAMPLE;
  event->thread = thread;
  event->header.flags = miteruby_rb_profile_frames(event->thread.value, MITERUBY_MAX_FRAMES, &view);
  if (from_signal_handler) event->header.flags |= MITERUBY_EVENT_FROM_SIGNAL_HANDLER;
  event->header.frame_count = view.frame_count;

  // Positions follow the captured refs, not the reserved capacity.
  memcpy(&event->refs[view.frame_count], positions, view.frame_count * sizeof(positions[0]));
  size_t size_bytes = sizeof(*event) + view.frame_count * (sizeof(event->refs[0]) + sizeof(positions[0]));
  event->header.size_bytes = round_up_to_8_bytes(size_bytes);

  return miteruby_buffer_try_write(buffer, storage.words, event->header.size_bytes / sizeof(uint64_t), signal_mask);
}

static inline size_t round_up_to_8_bytes(size_t size_bytes) {
  return (size_bytes + 7) & ~(size_t) 7;
}
