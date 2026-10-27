#pragma once

#ifndef __APPLE__
#include <semaphore.h>
#endif
#include <signal.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// TODO: Currently buffer capacity is fixed, we should consider making it configurable
#define MITERUBY_BUFFER_CAPACITY_BYTES (1024U * 1024U)

_Static_assert(MITERUBY_BUFFER_CAPACITY_BYTES % sizeof(uint64_t) == 0, "buffer capacity must be divisible by 8 bytes");
_Static_assert(MITERUBY_BUFFER_CAPACITY_BYTES >= 16U, "buffer capacity must be at least 16 bytes");
_Static_assert((MITERUBY_BUFFER_CAPACITY_BYTES & (MITERUBY_BUFFER_CAPACITY_BYTES - 1U)) == 0, "buffer capacity must be a power of two");

// Multiple producers, exactly one consumer.
// Producers are serialized by a CAS spinlock. The consumer never takes it.
// Inspired by Go's CPU profiler and its `profBuf` buffer. See `design/BufferDesign.md` for details.
//
// On the producer side, this is designed to be used from both signal handlers and normal code:
// * Normal code passes a signal set to block before locking and unblock after unlocking (so as to not get interrupted)
// * Signal handlers pass NULL and must prevent nested producer handlers.
//
// Fields are exposed for stack allocation, not for concurrent caller access.
typedef struct {
  _Atomic uint32_t producer_lock;

  // Borrowed from the current producer and protected by producer_lock.
  // NULL means no mask operations on unlock.
  const sigset_t *locked_signal_mask;

  _Atomic uint64_t read_position;  // Published boundary of reusable words.
  _Atomic uint64_t write_state;    // Low 32 bits: position; high bits: flags.
  _Atomic uint64_t rejected_count; // Pending rejected attempts, out of band.
  _Atomic bool closed;

  // Consumer-owned boundary; published on the next read to release the item.
  uint32_t next_read_position;
  #ifndef __APPLE__
      sem_t consumer_wakeup;
  #endif

  uint64_t data[MITERUBY_BUFFER_CAPACITY_BYTES / sizeof(uint64_t)];
} miteruby_buffer_t;

typedef struct {
  // Borrowed until the next read. Non-NULL also identifies a zero-length item.
  const uint64_t *data;
  uint16_t length; // Payload word count, excluding the one-word length prefix.
  uint64_t rejected_count; // Failed write attempts, not necessarily lost items.
  bool end_of_stream;
  bool interrupted;
  bool internal_error;
} miteruby_buffer_record_t;

// Returns 0 on success, -1 with errno set if semaphore initialization fails.
int miteruby_buffer_init(miteruby_buffer_t *buffer);
// Destroy only after all producers and the consumer have stopped.
void miteruby_buffer_destroy(miteruby_buffer_t *buffer);

// May spin/yield for the producer lock, but never waits for buffer space.
// Copies length_words uint64_t words; the source may be reused after return.
// Each item occupies one total-length word followed by the payload words.
// Records stay contiguous. If one cannot fit at the end, a zero rewind marker
// skips the remaining tail; both the skipped words and record must fit.
// NULL data is valid only for length_words 0. The uint16_t argument limits
// payloads to UINT16_MAX words; source words must stay valid until return.
// False means insufficient space or NULL data with nonzero length;
// nothing is published and one rejected attempt is recorded. Only
// valid items can succeed on retry. Handlers must return on rejection.
// Concurrent producers are ordered by lock acquisition, not invocation time.
// signal_mask points to a prepared set of blockable producer signals, or NULL
// to skip masking (inside a handler, with external masking, or without signals).
// The set must remain valid and unchanged until this call returns.
// Successful and rejected writes both unblock every signal in the set,
// including signals already blocked on entry. Signals outside it are untouched.
// Mask-operation and semaphore-post failures are fatal.
bool miteruby_buffer_try_write(miteruby_buffer_t *buffer, const uint64_t *data, uint16_t length_words,
                              const sigset_t *signal_mask);
// Call once, after ALL producers (including handlers) have finished writing.
// Signals that no more items will arrive and wakes a sleeping consumer.
// On macOS, the consumer observes close on its next poll.
// The consumer drains remaining items and rejection counts, then receives
// end_of_stream = true so its read loop can terminate.
// Uses the same signal_mask convention. Closing does not prevent writes;
// the caller must stop producers first and ensure no writes occur after close.
void miteruby_buffer_close(miteruby_buffer_t *buffer, const sigset_t *signal_mask);

// Consumer only. Releases the previous item, then returns one complete item,
// a rejection count, or EOF. data != NULL means an item, even when length is 0.
// Rewind markers are skipped internally; payloads are always borrowed directly
// from the ring. Empty items have a stored total length of 1, not a rewind marker.
// With interrupted=NULL, reads never block; an all-zero result means nothing is available yet.
// Otherwise reads block until data, EOF, or interruption. Keep the flag alive throughout the read;
// to interrupt, set it to true before calling miteruby_buffer_wake_consumer.
// Interruption leaves unread records available for a later read.
// internal_error means invalid framing or a failed wait; the consumer must stop reading.
// On macOS, blocking reads poll every 100 ms while empty; available items
// return immediately. Other platforms use semaphore notifications.
// EOF follows all items and rejection reports.
miteruby_buffer_record_t miteruby_buffer_read(
    miteruby_buffer_t *buffer, atomic_bool *interrupted);

// May run concurrently with the reader, including from a signal handler. macOS readers notice interrupts on their next poll.
void miteruby_buffer_wake_consumer(miteruby_buffer_t *buffer);

typedef void (*miteruby_buffer_visitor_t)(const uint64_t *data);

// Visits a fixed snapshot, including the consumer's borrowed record, without consuming anything.
// Holds the producer lock; consumers may advance, but released storage cannot be overwritten.
// signal_mask must be non-NULL and include the producer signals.
// Those signals are blocked before locking and unconditionally unblocked after unlocking.
// Callbacks must not mutate records, reenter the producer/visitor, raise, or trigger GC.
// Lock holders must not allocate Ruby objects or wait for the GVL: GC may be waiting for this lock.
void miteruby_buffer_visit(miteruby_buffer_t *buffer, miteruby_buffer_visitor_t visit, const sigset_t *signal_mask);
