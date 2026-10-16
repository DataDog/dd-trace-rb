#include <ruby.h>

#include "sample_event.h"
#include "../private_vm_api_access.h"
#include "../time_helpers.h"

#include <errno.h>
#include <string.h>

#define MAX_FRAMES 400
#define MAX_SIZE_BYTES \
  ((sizeof(miteruby_event_stack_sample_t) + MAX_FRAMES * \
    (sizeof(miteruby_event_frame_refs_t) + sizeof(miteruby_event_frame_position_t)) + 7) & ~(size_t) 7)

static inline size_t round_up_to_8_bytes(size_t size_bytes) {
  return (size_bytes + 7) & ~(size_t) 7;
}

// TODO: Move away from hardcoded limit of 400 frames
// TODO: Consider finally moving to upstream rb_profile_frames
bool miteruby_sample_event_publish(miteruby_buffer_t *buffer) {
  int saved_errno = errno; // defensive copy for when we run in a signal handler
  union {
    miteruby_event_stack_sample_t event;
    uint64_t words[MAX_SIZE_BYTES / sizeof(uint64_t)];
  } storage = {.words = {0}};
  miteruby_event_frame_position_t positions[MAX_FRAMES];
  miteruby_event_stack_sample_t *event = &storage.event;
  miteruby_event_stack_sample_view_t view = {.refs = event->refs, .positions = positions};

  event->header.timestamp_ns = monotonic_wall_time_now_ns();
  event->header.type = MITERUBY_EVENT_STACK_SAMPLE;
  event->thread.value = rb_thread_current();
  event->header.flags = miteruby_rb_profile_frames(event->thread.value, MAX_FRAMES, &view);
  event->header.frame_count = view.frame_count;

  // Positions follow the captured refs, not the reserved capacity.
  memcpy(&event->refs[view.frame_count], positions, view.frame_count * sizeof(positions[0]));
  size_t size_bytes = sizeof(*event) + view.frame_count * (sizeof(event->refs[0]) + sizeof(positions[0]));
  event->header.size_bytes = round_up_to_8_bytes(size_bytes);

  bool published = miteruby_buffer_try_write(buffer, storage.words, event->header.size_bytes / sizeof(uint64_t), NULL);
  errno = saved_errno;
  return published;
}
