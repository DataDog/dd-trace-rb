#include "buffer.h"

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MITERUBY_BUFFER_CAPACITY_WORDS \
    (MITERUBY_BUFFER_CAPACITY_BYTES / sizeof(uint64_t))

#define MITERUBY_BUFFER_CONSUMER_SLEEPING (UINT64_C(1) << 32)
#define MITERUBY_BUFFER_EXTRA_PENDING     (UINT64_C(1) << 33)

// GCC/Clang compile-time checks by size; 0 requests the usual alignment.
// __extension__ permits the builtin in an assertion under GCC's -Wpedantic.
__extension__ _Static_assert(__atomic_always_lock_free(sizeof(uint32_t), 0),
               "buffer requires always-lock-free uint32_t atomics");
__extension__ _Static_assert(__atomic_always_lock_free(sizeof(uint64_t), 0),
               "buffer requires always-lock-free uint64_t atomics");
__extension__ _Static_assert(__atomic_always_lock_free(sizeof(bool), 0),
               "buffer requires always-lock-free bool atomics");

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

static uint32_t miteruby_buffer_advance_position(uint32_t position, uint32_t word_count)
{
    // Wrap at 32 bits before widening into write_state, keeping flags separate.
    return position + word_count;
}

static uint32_t miteruby_buffer_unread_count(uint32_t write_position, uint32_t read_position)
{
    // Unsigned subtraction also works when the write position has wrapped.
    return write_position - read_position;
}

void miteruby_buffer_wake_consumer(miteruby_buffer_t *buffer)
{
#ifdef __APPLE__
    (void)buffer; // Polling readers never set the sleeping flag.
#else
    // Unlike a condition-variable signal, a semaphore remembers a wakeup that
    // arrives between the consumer setting its sleeping flag and sem_wait.
    if (sem_post(&buffer->consumer_wakeup) != 0)
        abort();
#endif
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
#ifdef __APPLE__
    return 0;
#else
    return sem_init(&buffer->consumer_wakeup, 0, 0);
#endif
}

void miteruby_buffer_destroy(miteruby_buffer_t *buffer)
{
#ifdef __APPLE__
    (void)buffer;
#else
    if (sem_destroy(&buffer->consumer_wakeup) != 0)
        abort();
#endif
}

bool miteruby_buffer_try_write(miteruby_buffer_t *buffer, const uint64_t *data, uint16_t length_words,
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
    uint32_t free_words = MITERUBY_BUFFER_CAPACITY_WORDS -
                         miteruby_buffer_unread_count(write_position, read_position);
    uint32_t record_length = 1U + length_words;
    uint32_t offset = write_position % MITERUBY_BUFFER_CAPACITY_WORDS;
    uint32_t tail_words = MITERUBY_BUFFER_CAPACITY_WORDS - offset;
    uint32_t skipped_words = record_length > tail_words ? tail_words : 0;
    if ((length_words != 0 && data == NULL) ||
        skipped_words + record_length > free_words) {
        atomic_fetch_add(&buffer->rejected_count, 1);
        miteruby_buffer_notify_extra(buffer);
        miteruby_buffer_producer_unlock(buffer);
        return false;
    }

    // Check space before writing anything, including the rewind marker.
    if (skipped_words != 0) {
        buffer->data[offset] = 0;
        offset = 0;
    }
    buffer->data[offset] = record_length;
    if (length_words != 0)
        memcpy(&buffer->data[offset + 1], data, (size_t)length_words * sizeof(*data));
    for (;;) {
        // Advancing the position clears both flags.
        uint64_t next_write_state = miteruby_buffer_advance_position(
            write_position, skipped_words + record_length);
        uint32_t unread_count = miteruby_buffer_unread_count(
            miteruby_buffer_position_from_state(next_write_state),
            miteruby_buffer_position_from_state(atomic_load(&buffer->read_position)));
        if (unread_count < MITERUBY_BUFFER_CAPACITY_WORDS / 2)
            next_write_state |= current_write_state & MITERUBY_BUFFER_CONSUMER_SLEEPING;

        // Publish the skipped tail, prefix and payload with one position update,
        // racing only with the reader's flag changes. Partial items stay hidden.
        // C11's default seq_cst ordering deliberately matches Go's atomics.
        if (atomic_compare_exchange_weak(&buffer->write_state, &current_write_state,
                                        next_write_state)) {
            if (unread_count >= MITERUBY_BUFFER_CAPACITY_WORDS / 2 &&
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

miteruby_buffer_record_t miteruby_buffer_read(
    miteruby_buffer_t *buffer, atomic_bool *interrupted)
{
    uint32_t read_position = buffer->next_read_position;
    // The caller has finished using the last item. Only now may producers
    // reuse its words; this store orders the caller's reads before reuse.
    atomic_store(&buffer->read_position, read_position);

    for (;;) {
        if (interrupted != NULL && atomic_load(interrupted))
            return (miteruby_buffer_record_t){.interrupted = true};
        uint64_t write_state = atomic_load(&buffer->write_state);
        uint32_t available_count = miteruby_buffer_unread_count(
            miteruby_buffer_position_from_state(write_state), read_position);
        if (available_count != 0) {
            uint32_t offset = read_position % MITERUBY_BUFFER_CAPACITY_WORDS;
            uint64_t record_length = buffer->data[offset];
            if (record_length == 0) {
                uint32_t skipped_words = MITERUBY_BUFFER_CAPACITY_WORDS - offset;
                // The writer publishes a rewind together with a complete record.
                if (skipped_words >= available_count)
                    abort();
                read_position = miteruby_buffer_advance_position(read_position, skipped_words);
                available_count -= skipped_words;
                offset = 0;
                record_length = buffer->data[offset];
            }
            if (record_length == 0 || record_length > UINT16_MAX + 1U ||
                record_length > available_count || record_length > MITERUBY_BUFFER_CAPACITY_WORDS - offset)
                abort();
            buffer->next_read_position = miteruby_buffer_advance_position(
                read_position, (uint32_t)record_length);
            return (miteruby_buffer_record_t){
                .data = &buffer->data[offset + 1], .length = (uint16_t)(record_length - 1)};
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
        if (interrupted == NULL)
            return (miteruby_buffer_record_t){0};

#ifdef __APPLE__
        // Like Go on Darwin, poll instead of waking from the signal handler.
        // Sleep only while empty: this API returns one record per call.
        const struct timespec delay = {.tv_nsec = 100 * 1000 * 1000};
        if (nanosleep(&delay, NULL) != 0 && errno != EINTR)
            abort();
#else
        // If the producer publishes data/EOF/rejections first, this CAS fails
        // and we look again. If we win, the producer inherits the obligation
        // to wake us at the half-full threshold, on rejection, or on close.
        if (!atomic_compare_exchange_strong(&buffer->write_state, &write_state,
                                           write_state | MITERUBY_BUFFER_CONSUMER_SLEEPING))
            continue;
        if (atomic_load(interrupted))
            return (miteruby_buffer_record_t){.interrupted = true};
        if (sem_wait(&buffer->consumer_wakeup) != 0 && errno != EINTR)
            abort();
#endif
    }
}

void miteruby_buffer_visit(miteruby_buffer_t *buffer, miteruby_buffer_visitor_t visit, const sigset_t *signal_mask)
{
    miteruby_buffer_producer_lock_mask(buffer, signal_mask);

    uint32_t position = (uint32_t)atomic_load(&buffer->read_position);
    uint32_t remaining = miteruby_buffer_unread_count(
        miteruby_buffer_position_from_state(atomic_load(&buffer->write_state)), position);

    while (remaining != 0) {
        uint32_t offset = position % MITERUBY_BUFFER_CAPACITY_WORDS;
        uint64_t record_length = buffer->data[offset];
        if (record_length == 0) {
            uint32_t skipped_words = MITERUBY_BUFFER_CAPACITY_WORDS - offset;
            position = miteruby_buffer_advance_position(position, skipped_words);
            remaining -= skipped_words;
            continue;
        }

        visit(&buffer->data[offset + 1]);
        position = miteruby_buffer_advance_position(position, (uint32_t)record_length);
        remaining -= (uint32_t)record_length;
    }

    miteruby_buffer_producer_unlock(buffer);
}
