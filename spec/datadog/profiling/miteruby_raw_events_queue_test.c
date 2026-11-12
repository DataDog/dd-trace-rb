#include "raw_events_queue.h"

#include <ruby.h>
#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <threads.h>
#include <unistd.h>
#include <errno.h>
#include "../../../ext/datadog_profiling_native_extension/time_helpers.h"

static miteruby_raw_events_queue_t raw_events_queue;
static long timestamp_clock;

static long test_monotonic_time(void)
{
    assert(atomic_load(&raw_events_queue.producer_lock) == 1);
    return ++timestamp_clock;
}

static unsigned wait_failures;
#ifdef __APPLE__
static int test_nanosleep(const struct timespec *delay, struct timespec *remaining) {
    if (wait_failures == 0) return nanosleep(delay, remaining);
    errno = --wait_failures ? EINTR : EINVAL;
    return -1;
}
#define nanosleep test_nanosleep
#else
static int test_sem_wait(sem_t *semaphore) {
    if (wait_failures == 0) return sem_wait(semaphore);
    errno = --wait_failures ? EINTR : EINVAL;
    return -1;
}
#define sem_wait test_sem_wait
#endif
#define monotonic_wall_time_now_ns test_monotonic_time
#include "../../../ext/datadog_profiling_native_extension/miteruby/raw_events_queue.c"
#undef monotonic_wall_time_now_ns
#ifdef __APPLE__
#undef nanosleep
#else
#undef sem_wait
#endif

static volatile sig_atomic_t signal_delivered;

static struct {
    unsigned count;
    bool release_records;
    bool send_signal;
    bool consumer_ready;
    bool consumer_done;
    pthread_mutex_t mutex;
    pthread_cond_t condition;
} state = {
    .mutex = PTHREAD_MUTEX_INITIALIZER,
    .condition = PTHREAD_COND_INITIALIZER,
};
static unsigned empty_count;

static void produce_from_signal(int signal_number)
{
    (void)signal_number;
    union {
        struct { uint64_t values[2]; long timestamp; } payload;
        uint64_t words[3];
    } event = {.payload = {.values = {31, 32}, .timestamp = -1}};
    if (!miteruby_raw_events_queue_try_write(&raw_events_queue, event.words, 3, NULL, &event.payload.timestamp))
        _exit(3);
    signal_delivered = 1;
}

static void visit_record(const uint64_t *data)
{
    assert(data[0] == 11 + 10 * state.count);
    assert(data[1] == 12 + 10 * state.count);
    if (state.count++ != 0)
        return;

    if (state.release_records) {
        assert(pthread_mutex_lock(&state.mutex) == 0);
        state.consumer_ready = true;
        assert(pthread_cond_signal(&state.condition) == 0);
        while (!state.consumer_done)
            assert(pthread_cond_wait(&state.condition, &state.mutex) == 0);
        assert(pthread_mutex_unlock(&state.mutex) == 0);
        assert(data[0] == 11 && data[1] == 12);
    }
    if (state.send_signal) {
        assert(raise(SIGPROF) == 0);
        assert(signal_delivered == 0);
    }
}

static void *consume_records(void *arg)
{
    (void)arg;
    assert(pthread_mutex_lock(&state.mutex) == 0);
    while (!state.consumer_ready)
        assert(pthread_cond_wait(&state.condition, &state.mutex) == 0);
    miteruby_raw_events_queue_record_t record = miteruby_raw_events_queue_read(&raw_events_queue, NULL);
    assert(record.length == 2 && record.data[0] == 21 && record.data[1] == 22);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data == NULL);
    state.consumer_done = true;
    assert(pthread_cond_signal(&state.condition) == 0);
    assert(pthread_mutex_unlock(&state.mutex) == 0);
    return NULL;
}

static void visit_empty_record(const uint64_t *data)
{
    assert(data != NULL);
    empty_count++;
}

typedef struct {
    atomic_bool started;
    atomic_bool interrupted;
    miteruby_raw_events_queue_record_t result;
} interrupt_test_state;

static int interruptible_reader(void *context)
{
    interrupt_test_state *test = context;
    atomic_store(&test->started, true);
    test->result = miteruby_raw_events_queue_read(&raw_events_queue, &test->interrupted);
    return 0;
}

static void test_interruptible_read(void)
{
    interrupt_test_state test = {0};
    atomic_init(&test.started, false);
    atomic_init(&test.interrupted, false);
    miteruby_raw_events_queue_wake_consumer(&raw_events_queue);
    thrd_t reader;
    assert(thrd_create(&reader, interruptible_reader, &test) == thrd_success);
    while (!atomic_load(&test.started))
        thrd_yield();
#ifndef __APPLE__
    int pending_wakeups;
    do {
        assert(sem_getvalue(&raw_events_queue.consumer_wakeup, &pending_wakeups) == 0);
        thrd_yield();
    } while (pending_wakeups != 0);
#endif
    atomic_store(&test.interrupted, true);
    miteruby_raw_events_queue_wake_consumer(&raw_events_queue);
    assert(thrd_join(reader, NULL) == thrd_success);
    assert(test.result.interrupted && !test.result.end_of_stream && test.result.data == NULL);

    uint64_t value = 77;
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, &value, 1, NULL, NULL));
    test.result = miteruby_raw_events_queue_read(&raw_events_queue, &test.interrupted);
    assert(test.result.interrupted);
    atomic_store(&test.interrupted, false);
    test.result = miteruby_raw_events_queue_read(&raw_events_queue, &test.interrupted);
    assert(!test.result.interrupted && test.result.data[0] == value);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data == NULL);
}

static void test_internal_errors(void)
{
    const uint32_t capacity = MITERUBY_RAW_EVENTS_QUEUE_CAPACITY_BYTES / sizeof(uint64_t);
    const struct {
        uint32_t position;
        uint32_t available;
        uint64_t length;
    } cases[] = {
        {capacity - 1, 1, 0},
        {capacity - 1, 2, 0},
        {0, UINT16_MAX + 2U, UINT16_MAX + 2U},
        {0, 1, 2},
        {capacity - 1, 2, 2},
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        assert(miteruby_raw_events_queue_init(&raw_events_queue) == 0);
        raw_events_queue.next_read_position = cases[i].position;
        raw_events_queue.data[0] = 0;
        raw_events_queue.data[cases[i].position] = cases[i].length;
        atomic_store(&raw_events_queue.write_state, cases[i].position + cases[i].available);
        miteruby_raw_events_queue_record_t record = miteruby_raw_events_queue_read(&raw_events_queue, NULL);
        assert(record.internal_error && record.data == NULL);
        assert(!record.interrupted && !record.end_of_stream && record.rejected_count == 0);
        assert(raw_events_queue.next_read_position == cases[i].position);
        miteruby_raw_events_queue_destroy(&raw_events_queue);
    }

    assert(miteruby_raw_events_queue_init(&raw_events_queue) == 0);
    atomic_bool interrupted = false;
    wait_failures = 2;
    miteruby_raw_events_queue_record_t record = miteruby_raw_events_queue_read(&raw_events_queue, &interrupted);
    assert(wait_failures == 0);
    assert(record.internal_error && record.data == NULL);
    assert(!record.interrupted && !record.end_of_stream);
    miteruby_raw_events_queue_destroy(&raw_events_queue);
}

static void test_timestamp_destination(void)
{
    assert(miteruby_raw_events_queue_init(&raw_events_queue) == 0);
    uint32_t start = MITERUBY_RAW_EVENTS_QUEUE_CAPACITY_WORDS - 1;
    atomic_store(&raw_events_queue.read_position, start);
    atomic_store(&raw_events_queue.write_state, start);
    raw_events_queue.next_read_position = start;
    union {
        struct { uint64_t marker; long timestamp; } payload;
        uint64_t words[2];
    } event = {.payload = {.marker = 42, .timestamp = -1}};
    timestamp_clock = 100;
    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGPROF);
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, event.words, 2, &mask, &event.payload.timestamp));
    assert(event.payload.timestamp == 101);
    miteruby_raw_events_queue_record_t record = miteruby_raw_events_queue_read(&raw_events_queue, NULL);
    assert(record.length == 2 && record.data[0] == 42 && record.data[1] == 101);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data == NULL);

    long separate_timestamp = -1;
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, event.words, 2, NULL, &separate_timestamp));
    assert(separate_timestamp == 102 && event.payload.timestamp == 101);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data[1] == 101);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data == NULL);
    assert(!miteruby_raw_events_queue_try_write(&raw_events_queue, NULL, 1, NULL, &separate_timestamp));
    assert(separate_timestamp == 102 && timestamp_clock == 102);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).rejected_count == 1);
    miteruby_raw_events_queue_destroy(&raw_events_queue);

    assert(miteruby_raw_events_queue_init(&raw_events_queue) == 0);
    static const uint64_t filler[UINT16_MAX] = {0};
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, filler, UINT16_MAX, NULL, NULL));
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, filler, UINT16_MAX, NULL, NULL));
    event.payload.timestamp = -1;
    assert(!miteruby_raw_events_queue_try_write(&raw_events_queue, event.words, 2, NULL, &event.payload.timestamp));
    assert(event.payload.timestamp == -1 && timestamp_clock == 102);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).length == UINT16_MAX);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).length == UINT16_MAX);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).rejected_count == 1);
    miteruby_raw_events_queue_destroy(&raw_events_queue);
}

static int timestamp_producer(void *arg)
{
    unsigned id = *(unsigned *)arg;
    for (unsigned i = 0; i < 128; i++) {
        union {
            struct { uint64_t value; long timestamp; } payload;
            uint64_t words[2];
        } event = {.payload = {.value = ((uint64_t)id << 32) | i, .timestamp = -1}};
        assert(miteruby_raw_events_queue_try_write(&raw_events_queue, event.words, 2, NULL, &event.payload.timestamp));
    }
    return 0;
}

static void test_timestamp_order(void)
{
    assert(miteruby_raw_events_queue_init(&raw_events_queue) == 0);
    timestamp_clock = 0;
    thrd_t producers[4];
    unsigned ids[] = {0, 1, 2, 3}, next[4] = {0};
    for (unsigned i = 0; i < 4; i++)
        assert(thrd_create(&producers[i], timestamp_producer, &ids[i]) == thrd_success);
    for (unsigned i = 0; i < 4; i++)
        assert(thrd_join(producers[i], NULL) == thrd_success);
    for (unsigned i = 0; i < 4 * 128; i++) {
        miteruby_raw_events_queue_record_t record = miteruby_raw_events_queue_read(&raw_events_queue, NULL);
        assert(record.length == 2 && record.data[1] == i + 1);
        unsigned id = record.data[0] >> 32;
        assert(id < 4 && (uint32_t)record.data[0] == next[id]++);
    }
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data == NULL);
    miteruby_raw_events_queue_destroy(&raw_events_queue);
}

int main(int argc, char **argv)
{
    ruby_sysinit(&argc, &argv);
    RUBY_INIT_STACK;
    ruby_init();
    alarm(10);
    assert(miteruby_raw_events_queue_init(&raw_events_queue) == 0);
    sigset_t mask, original_mask, current_mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGPROF);
    assert(pthread_sigmask(SIG_UNBLOCK, &mask, &original_mask) == 0);

    // Exercise both the ring rewind marker and uint32_t position wraparound.
    uint32_t start = UINT32_MAX - 3;
    atomic_store(&raw_events_queue.read_position, start);
    atomic_store(&raw_events_queue.write_state, start);
    raw_events_queue.next_read_position = start;
    const uint64_t first[] = {11, 12}, second[] = {21, 22};
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, first, 2, NULL, NULL));
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, second, 2, NULL, NULL));
    miteruby_raw_events_queue_visit(&raw_events_queue, visit_record, &mask);
    assert(state.count == 2);
    miteruby_raw_events_queue_record_t borrowed = miteruby_raw_events_queue_read(&raw_events_queue, NULL);
    assert(borrowed.length == 2 && borrowed.data[0] == 11);

    state.count = 0;
    state.release_records = true;
    pthread_t consumer;
    assert(pthread_create(&consumer, NULL, consume_records, NULL) == 0);
    miteruby_raw_events_queue_visit(&raw_events_queue, visit_record, &mask);
    assert(state.count == 2);
    assert(pthread_join(consumer, NULL) == 0);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data == NULL);

    struct sigaction action = {.sa_handler = produce_from_signal}, previous_action;
    sigemptyset(&action.sa_mask);
    assert(sigaction(SIGPROF, &action, &previous_action) == 0);
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, first, 2, NULL, NULL));
    state.count = 0;
    state.release_records = false;
    state.send_signal = true;
    miteruby_raw_events_queue_visit(&raw_events_queue, visit_record, &mask);
    assert(state.count == 1 && signal_delivered == 1);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data[0] == 11);
    miteruby_raw_events_queue_record_t signaled = miteruby_raw_events_queue_read(&raw_events_queue, NULL);
    assert(signaled.length == 3 && signaled.data[0] == 31 && signaled.data[1] == 32 && signaled.data[2] == 1);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data == NULL);
    assert(sigaction(SIGPROF, &previous_action, NULL) == 0);

    assert(pthread_sigmask(SIG_BLOCK, &mask, NULL) == 0);
    assert(miteruby_raw_events_queue_try_write(&raw_events_queue, NULL, 0, NULL, NULL));
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).data != NULL);
    assert(!miteruby_raw_events_queue_try_write(&raw_events_queue, NULL, 1, NULL, NULL));
    miteruby_raw_events_queue_visit(&raw_events_queue, visit_empty_record, &mask);
    assert(empty_count == 1);
    assert(pthread_sigmask(SIG_BLOCK, NULL, &current_mask) == 0);
    assert(sigismember(&current_mask, SIGPROF) == 0);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).rejected_count == 1);
    miteruby_raw_events_queue_visit(&raw_events_queue, visit_empty_record, &mask);
    assert(empty_count == 1);

    assert(pthread_sigmask(SIG_SETMASK, &original_mask, NULL) == 0);
    assert(pthread_cond_destroy(&state.condition) == 0);
    assert(pthread_mutex_destroy(&state.mutex) == 0);
    test_interruptible_read();
    miteruby_raw_events_queue_close(&raw_events_queue, NULL);
    assert(miteruby_raw_events_queue_read(&raw_events_queue, NULL).end_of_stream);
    miteruby_raw_events_queue_destroy(&raw_events_queue);
    test_internal_errors();
    test_timestamp_destination();
    test_timestamp_order();
    alarm(0);
    return ruby_cleanup(0);
}
