#pragma once

#include <semaphore.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum {
    MITERUBY_BUFFER_CAPACITY = 100, // Bytes, including record length prefixes.
    MITERUBY_BUFFER_MAX_ITEM_SIZE = MITERUBY_BUFFER_CAPACITY - sizeof(uint16_t)
};

// Multiple producers, exactly one consumer. Initialize before starting any.
// Producers are serialized by a CAS spinlock. The consumer never takes it.
// Normal code passes a signal set to block before locking and unblock after
// unlocking. Handlers pass NULL and must prevent nested producer handlers.
// Fields are exposed for stack allocation, not for concurrent caller access.
typedef struct {
    _Atomic uint32_t producer_lock;
    // Borrowed from the current producer and protected by producer_lock.
    // NULL means no mask operations on unlock.
    const sigset_t *locked_signal_mask;
    _Atomic uint64_t read_position;  // Published boundary of reusable bytes.
    _Atomic uint64_t write_state;    // Low 32 bits: position; high bits: flags.
    _Atomic uint64_t rejected_count; // Pending rejected attempts, out of band.
    _Atomic bool closed;
    unsigned char data[MITERUBY_BUFFER_CAPACITY];
    // Consumer-owned boundary; published on the next read to release the item.
    uint32_t next_read_position;
    // Only wrapped payloads need copying to produce a contiguous read result.
    unsigned char read_scratch[MITERUBY_BUFFER_MAX_ITEM_SIZE];
    sem_t consumer_wakeup;          // Replacement for Go's runtime note.
} miteruby_buffer_t;

typedef struct {
    // Borrowed until the next read; use memcpy to decode typed values because
    // data need not be aligned. Non-NULL also identifies a zero-length item.
    const unsigned char *data;
    uint16_t length;
    uint64_t rejected_count; // Failed write attempts, not necessarily lost items.
    bool end_of_stream;
} miteruby_buffer_record_t;

// Returns 0 on success, -1 with errno set on failure (including non-lock-free
// atomics). Destroy only after all producers and the consumer have stopped.
int miteruby_buffer_init(miteruby_buffer_t *buffer);
void miteruby_buffer_destroy(miteruby_buffer_t *buffer);

// May spin/yield for the producer lock, but never waits for buffer space.
// Copies one complete item; the source may be reused as soon as this returns.
// NULL data is valid only for length 0. The maximum payload length is
// MITERUBY_BUFFER_MAX_ITEM_SIZE; source bytes must stay valid until return.
// False means insufficient space or invalid input (oversize/NULL with nonzero
// length); nothing is published and one rejected attempt is recorded. Only
// valid items can succeed on retry. Handlers must return on rejection.
// Concurrent producers are ordered by lock acquisition, not invocation time.
// signal_mask points to a prepared set of blockable producer signals, or NULL
// to skip masking (inside a handler, with external masking, or without signals).
// The set must remain valid and unchanged until this call returns.
// Successful and rejected writes both unblock every signal in the set,
// including signals already blocked on entry. Signals outside it are untouched.
// Mask-operation failures abort, like semaphore failures.
bool miteruby_buffer_try_write(miteruby_buffer_t *buffer, const void *data, uint16_t length,
                              const sigset_t *signal_mask);
// Call once, after ALL producers (including handlers) have finished writing.
// Signals that no more items will arrive and wakes a sleeping consumer.
// The consumer drains remaining items and rejection counts, then receives
// end_of_stream = true so its read loop can terminate.
// Uses the same signal_mask convention. Closing does not prevent writes;
// the caller must stop producers first and ensure no writes occur after close.
void miteruby_buffer_close(miteruby_buffer_t *buffer, const sigset_t *signal_mask);

// Consumer only. Releases the previous item, then returns one complete item,
// a rejection count, or EOF. data != NULL means an item, even when length is 0.
// Wrapped payloads are copied into consumer-owned scratch storage in the buffer.
// With blocking=false, an all-zero result means nothing is available yet.
// EOF follows all items and rejection reports.
miteruby_buffer_record_t miteruby_buffer_read(miteruby_buffer_t *buffer, bool blocking);
