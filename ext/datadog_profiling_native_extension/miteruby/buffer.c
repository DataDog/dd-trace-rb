#include "buffer.h"

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>

#define MITERUBY_BUFFER_CONSUMER_SLEEPING (UINT64_C(1) << 32)
#define MITERUBY_BUFFER_EXTRA_PENDING     (UINT64_C(1) << 33)

// Byte positions wrap modulo twice the capacity, distinguishing full from
// empty. Length prefixes and payloads can both cross the physical array end.
enum { MITERUBY_BUFFER_POSITION_MODULUS = 2 * MITERUBY_BUFFER_CAPACITY };

static void miteruby_buffer_producer_lock_internal(miteruby_buffer_t *buffer, const sigset_t *signal_mask)
{
    uint32_t expected_lock_state = 0;
    while (!atomic_compare_exchange_weak(&buffer->producer_lock, &expected_lock_state, 1)) {
        // CAS replaces expected_lock_state on failure; each attempt tests for 0.
        expected_lock_state = 0;
        // Like Go's cpuProfile.add: only producers wait, never the consumer.
        // Handler use targets Linux/glibc, which documents sched_yield AS-safe.
        // The handler mask or lock_mask must already block producing signals.
        sched_yield();
    }
    buffer->locked_signal_mask = signal_mask;
}

static void miteruby_buffer_producer_lock_sighandler(miteruby_buffer_t *buffer)
{
    miteruby_buffer_producer_lock_internal(buffer, NULL);
}

static void miteruby_buffer_producer_lock_mask(miteruby_buffer_t *buffer, const sigset_t *signal_mask)
{
    if (pthread_sigmask(SIG_BLOCK, signal_mask, NULL) != 0)
        abort();
    miteruby_buffer_producer_lock_internal(buffer, signal_mask);
}

static void miteruby_buffer_producer_unlock(miteruby_buffer_t *buffer)
{
    // Snapshot before release: another producer can immediately replace this
    // pointer. The caller keeps the pointed-to set valid until we return.
    const sigset_t *signal_mask = buffer->locked_signal_mask;
    // A pending handler may run inside pthread_sigmask, so release first.
    atomic_store(&buffer->producer_lock, 0);
    if (signal_mask != NULL && pthread_sigmask(SIG_UNBLOCK, signal_mask, NULL) != 0)
        abort();
}

static uint32_t miteruby_buffer_position_from_state(uint64_t state)
{
    return (uint32_t)state;
}

static uint32_t miteruby_buffer_advance_position(uint32_t position, uint32_t byte_count)
{
    return (position + byte_count) % MITERUBY_BUFFER_POSITION_MODULUS;
}

static uint32_t miteruby_buffer_unread_count(uint32_t write_position, uint32_t read_position)
{
    return (write_position + MITERUBY_BUFFER_POSITION_MODULUS - read_position) % MITERUBY_BUFFER_POSITION_MODULUS;
}

static void miteruby_buffer_copy_in(miteruby_buffer_t *buffer, uint32_t position,
                                   const void *source, size_t length)
{
    if (length == 0)
        return;
    size_t offset = position % MITERUBY_BUFFER_CAPACITY;
    size_t first_length = MITERUBY_BUFFER_CAPACITY - offset;
    if (first_length > length)
        first_length = length;
    memcpy(&buffer->data[offset], source, first_length);
    if (first_length < length)
        memcpy(buffer->data, (const unsigned char *)source + first_length,
               length - first_length);
}

static void miteruby_buffer_copy_out(const miteruby_buffer_t *buffer, uint32_t position,
                                    void *destination, size_t length)
{
    if (length == 0)
        return;
    size_t offset = position % MITERUBY_BUFFER_CAPACITY;
    size_t first_length = MITERUBY_BUFFER_CAPACITY - offset;
    if (first_length > length)
        first_length = length;
    memcpy(destination, &buffer->data[offset], first_length);
    if (first_length < length)
        memcpy((unsigned char *)destination + first_length, buffer->data,
               length - first_length);
}

static void miteruby_buffer_wake_consumer(miteruby_buffer_t *buffer)
{
    // Unlike a condition-variable signal, a semaphore remembers a wakeup that
    // arrives between the consumer setting its sleeping flag and sem_wait.
    if (sem_post(&buffer->consumer_wakeup) != 0)
        abort();
}

static void miteruby_buffer_notify_extra(miteruby_buffer_t *buffer)
{
    uint64_t current_write_state = atomic_load(&buffer->write_state);
    for (;;) {
        uint64_t next_write_state =
            (current_write_state | MITERUBY_BUFFER_EXTRA_PENDING) & ~MITERUBY_BUFFER_CONSUMER_SLEEPING;
        if (atomic_compare_exchange_weak(&buffer->write_state, &current_write_state,
                                        next_write_state)) {
            if (current_write_state & MITERUBY_BUFFER_CONSUMER_SLEEPING)
                miteruby_buffer_wake_consumer(buffer);
            return;
        }
    }
}

int miteruby_buffer_init(miteruby_buffer_t *buffer)
{
    atomic_init(&buffer->producer_lock, 0);
    buffer->locked_signal_mask = NULL;
    atomic_init(&buffer->read_position, 0);
    atomic_init(&buffer->write_state, 0);
    atomic_init(&buffer->rejected_count, 0);
    atomic_init(&buffer->closed, false);
    buffer->next_read_position = 0;
    if (!atomic_is_lock_free(&buffer->producer_lock) ||
        !atomic_is_lock_free(&buffer->read_position) ||
        !atomic_is_lock_free(&buffer->write_state) ||
        !atomic_is_lock_free(&buffer->rejected_count) ||
        !atomic_is_lock_free(&buffer->closed)) {
        errno = ENOTSUP;
        return -1;
    }
    return sem_init(&buffer->consumer_wakeup, 0, 0);
}

void miteruby_buffer_destroy(miteruby_buffer_t *buffer)
{
    if (sem_destroy(&buffer->consumer_wakeup) != 0)
        abort();
}

bool miteruby_buffer_try_write(miteruby_buffer_t *buffer, const void *data, uint16_t length,
                              const sigset_t *signal_mask)
{
    // Hold through publication AND wakeup, including the full-buffer path.
    if (signal_mask != NULL)
        miteruby_buffer_producer_lock_mask(buffer, signal_mask);
    else
        miteruby_buffer_producer_lock_sighandler(buffer);
    uint64_t current_write_state = atomic_load(&buffer->write_state);
    uint32_t write_position = miteruby_buffer_position_from_state(current_write_state);
    uint32_t read_position = miteruby_buffer_position_from_state(atomic_load(&buffer->read_position));
    uint32_t free_bytes = MITERUBY_BUFFER_CAPACITY -
                         miteruby_buffer_unread_count(write_position, read_position);
    if (length > MITERUBY_BUFFER_MAX_ITEM_SIZE || (length != 0 && data == NULL) ||
        sizeof(uint16_t) + length > free_bytes) {
        atomic_fetch_add(&buffer->rejected_count, 1);
        miteruby_buffer_notify_extra(buffer);
        miteruby_buffer_producer_unlock(buffer);
        return false;
    }

    uint16_t payload_length = length;
    uint32_t record_length = sizeof(payload_length) + payload_length;
    uint32_t payload_position = miteruby_buffer_advance_position(
        write_position, sizeof(payload_length));
    // The prefix is internal, native-endian metadata. memcpy avoids alignment
    // assumptions, including when the prefix itself wraps around the ring.
    miteruby_buffer_copy_in(buffer, write_position, &payload_length, sizeof(payload_length));
    miteruby_buffer_copy_in(buffer, payload_position, data, length);
    for (;;) {
        // Advancing the position clears both flags.
        uint64_t next_write_state = miteruby_buffer_advance_position(write_position, record_length);
        uint32_t unread_count = miteruby_buffer_unread_count(
            miteruby_buffer_position_from_state(next_write_state),
            miteruby_buffer_position_from_state(atomic_load(&buffer->read_position)));
        if (unread_count < MITERUBY_BUFFER_CAPACITY / 2)
            next_write_state |= current_write_state & MITERUBY_BUFFER_CONSUMER_SLEEPING;

        // Publish the entire prefix and payload with one position update,
        // racing only with the reader's flag changes. Partial items stay hidden.
        // C11's default seq_cst ordering deliberately matches Go's atomics.
        if (atomic_compare_exchange_weak(&buffer->write_state, &current_write_state,
                                        next_write_state)) {
            if (unread_count >= MITERUBY_BUFFER_CAPACITY / 2 &&
                (current_write_state & MITERUBY_BUFFER_CONSUMER_SLEEPING))
                miteruby_buffer_wake_consumer(buffer);
            miteruby_buffer_producer_unlock(buffer);
            return true;
        }
    }
}

void miteruby_buffer_close(miteruby_buffer_t *buffer, const sigset_t *signal_mask)
{
    if (signal_mask != NULL)
        miteruby_buffer_producer_lock_mask(buffer, signal_mask);
    else
        miteruby_buffer_producer_lock_sighandler(buffer);
    atomic_store(&buffer->closed, true);
    miteruby_buffer_notify_extra(buffer);
    miteruby_buffer_producer_unlock(buffer);
}

miteruby_buffer_record_t miteruby_buffer_read(miteruby_buffer_t *buffer, bool blocking)
{
    uint32_t read_position = buffer->next_read_position;
    // The caller has finished using the last item. Only now may producers
    // reuse its bytes; this store orders the caller's reads before reuse.
    atomic_store(&buffer->read_position, read_position);

    for (;;) {
        uint64_t write_state = atomic_load(&buffer->write_state);
        uint32_t available_count = miteruby_buffer_unread_count(
            miteruby_buffer_position_from_state(write_state), read_position);
        if (available_count != 0) {
            uint16_t payload_length;
            if (available_count < sizeof(payload_length))
                abort();
            miteruby_buffer_copy_out(buffer, read_position, &payload_length, sizeof(payload_length));
            if (payload_length > MITERUBY_BUFFER_MAX_ITEM_SIZE ||
                sizeof(payload_length) + payload_length > available_count)
                abort();
            uint32_t payload_position = miteruby_buffer_advance_position(
                read_position, sizeof(payload_length));
            uint32_t offset = payload_position % MITERUBY_BUFFER_CAPACITY;
            const unsigned char *data = &buffer->data[offset];
            if (payload_length > MITERUBY_BUFFER_CAPACITY - offset) {
                miteruby_buffer_copy_out(buffer, payload_position,
                                        buffer->read_scratch, payload_length);
                data = buffer->read_scratch;
            }
            buffer->next_read_position = miteruby_buffer_advance_position(
                payload_position, payload_length);
            return (miteruby_buffer_record_t){.data = data, .length = payload_length};
        }

        // This port needs no timestamped overflow record. Only the reader
        // clears this counter, so exchange suffices; Go's two-sided overflow
        // flushing and generation counter are intentionally omitted.
        uint64_t rejected_count = atomic_exchange(&buffer->rejected_count, 0);
        if (rejected_count != 0)
            return (miteruby_buffer_record_t){.rejected_count = rejected_count};

        if (atomic_load(&buffer->closed)) {
            // Close may have raced with the earlier empty snapshot. Recheck
            // after observing EOF so we don't skip the producer's final data.
            if (miteruby_buffer_position_from_state(atomic_load(&buffer->write_state)) != read_position ||
                atomic_load(&buffer->rejected_count) != 0)
                continue;
            return (miteruby_buffer_record_t){.end_of_stream = true};
        }
        if (write_state & MITERUBY_BUFFER_EXTRA_PENDING) {
            atomic_compare_exchange_strong(&buffer->write_state, &write_state,
                                           write_state & ~MITERUBY_BUFFER_EXTRA_PENDING);
            continue;
        }
        if (!blocking)
            return (miteruby_buffer_record_t){0};

        // If the producer publishes data/EOF/rejections first, this CAS fails
        // and we look again. If we win, the producer inherits the obligation
        // to wake us at the half-full threshold, on rejection, or on close.
        if (!atomic_compare_exchange_strong(&buffer->write_state, &write_state,
                                           write_state | MITERUBY_BUFFER_CONSUMER_SLEEPING))
            continue;
        while (sem_wait(&buffer->consumer_wakeup) != 0) {
            if (errno != EINTR)
                abort();
        }
    }
}
