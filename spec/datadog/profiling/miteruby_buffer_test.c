#include "buffer.h"

#include <ruby.h>
#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <threads.h>
#include <unistd.h>
#include <errno.h>

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
#include "../../../ext/datadog_profiling_native_extension/miteruby/buffer.c"
#ifdef __APPLE__
#undef nanosleep
#else
#undef sem_wait
#endif

static miteruby_buffer_t buffer;
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
    const uint64_t words[] = {31, 32};
    if (!miteruby_buffer_try_write(&buffer, words, 2, NULL))
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
    miteruby_buffer_record_t record = miteruby_buffer_read(&buffer, NULL);
    assert(record.length == 2 && record.data[0] == 21 && record.data[1] == 22);
    assert(miteruby_buffer_read(&buffer, NULL).data == NULL);
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
    miteruby_buffer_record_t result;
} interrupt_test_state;

static int interruptible_reader(void *context)
{
    interrupt_test_state *test = context;
    atomic_store(&test->started, true);
    test->result = miteruby_buffer_read(&buffer, &test->interrupted);
    return 0;
}

static void test_interruptible_read(void)
{
    interrupt_test_state test = {0};
    atomic_init(&test.started, false);
    atomic_init(&test.interrupted, false);
    miteruby_buffer_wake_consumer(&buffer);
    thrd_t reader;
    assert(thrd_create(&reader, interruptible_reader, &test) == thrd_success);
    while (!atomic_load(&test.started))
        thrd_yield();
#ifndef __APPLE__
    int pending_wakeups;
    do {
        assert(sem_getvalue(&buffer.consumer_wakeup, &pending_wakeups) == 0);
        thrd_yield();
    } while (pending_wakeups != 0);
#endif
    atomic_store(&test.interrupted, true);
    miteruby_buffer_wake_consumer(&buffer);
    assert(thrd_join(reader, NULL) == thrd_success);
    assert(test.result.interrupted && !test.result.end_of_stream && test.result.data == NULL);

    uint64_t value = 77;
    assert(miteruby_buffer_try_write(&buffer, &value, 1, NULL));
    test.result = miteruby_buffer_read(&buffer, &test.interrupted);
    assert(test.result.interrupted);
    atomic_store(&test.interrupted, false);
    test.result = miteruby_buffer_read(&buffer, &test.interrupted);
    assert(!test.result.interrupted && test.result.data[0] == value);
    assert(miteruby_buffer_read(&buffer, NULL).data == NULL);
}

static void test_internal_errors(void)
{
    const uint32_t capacity = MITERUBY_BUFFER_CAPACITY_BYTES / sizeof(uint64_t);
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
        assert(miteruby_buffer_init(&buffer) == 0);
        buffer.next_read_position = cases[i].position;
        buffer.data[0] = 0;
        buffer.data[cases[i].position] = cases[i].length;
        atomic_store(&buffer.write_state, cases[i].position + cases[i].available);
        miteruby_buffer_record_t record = miteruby_buffer_read(&buffer, NULL);
        assert(record.internal_error && record.data == NULL);
        assert(!record.interrupted && !record.end_of_stream && record.rejected_count == 0);
        assert(buffer.next_read_position == cases[i].position);
        miteruby_buffer_destroy(&buffer);
    }

    assert(miteruby_buffer_init(&buffer) == 0);
    atomic_bool interrupted = false;
    wait_failures = 2;
    miteruby_buffer_record_t record = miteruby_buffer_read(&buffer, &interrupted);
    assert(wait_failures == 0);
    assert(record.internal_error && record.data == NULL);
    assert(!record.interrupted && !record.end_of_stream);
    miteruby_buffer_destroy(&buffer);
}

int main(int argc, char **argv)
{
    ruby_sysinit(&argc, &argv);
    RUBY_INIT_STACK;
    ruby_init();
    alarm(10);
    assert(miteruby_buffer_init(&buffer) == 0);
    sigset_t mask, original_mask, current_mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGPROF);
    assert(pthread_sigmask(SIG_UNBLOCK, &mask, &original_mask) == 0);

    // Exercise both the ring rewind marker and uint32_t position wraparound.
    uint32_t start = UINT32_MAX - 3;
    atomic_store(&buffer.read_position, start);
    atomic_store(&buffer.write_state, start);
    buffer.next_read_position = start;
    const uint64_t first[] = {11, 12}, second[] = {21, 22};
    assert(miteruby_buffer_try_write(&buffer, first, 2, NULL));
    assert(miteruby_buffer_try_write(&buffer, second, 2, NULL));
    miteruby_buffer_visit(&buffer, visit_record, &mask);
    assert(state.count == 2);
    miteruby_buffer_record_t borrowed = miteruby_buffer_read(&buffer, NULL);
    assert(borrowed.length == 2 && borrowed.data[0] == 11);

    state.count = 0;
    state.release_records = true;
    pthread_t consumer;
    assert(pthread_create(&consumer, NULL, consume_records, NULL) == 0);
    miteruby_buffer_visit(&buffer, visit_record, &mask);
    assert(state.count == 2);
    assert(pthread_join(consumer, NULL) == 0);
    assert(miteruby_buffer_read(&buffer, NULL).data == NULL);

    struct sigaction action = {.sa_handler = produce_from_signal}, previous_action;
    sigemptyset(&action.sa_mask);
    assert(sigaction(SIGPROF, &action, &previous_action) == 0);
    assert(miteruby_buffer_try_write(&buffer, first, 2, NULL));
    state.count = 0;
    state.release_records = false;
    state.send_signal = true;
    miteruby_buffer_visit(&buffer, visit_record, &mask);
    assert(state.count == 1 && signal_delivered == 1);
    assert(miteruby_buffer_read(&buffer, NULL).data[0] == 11);
    assert(miteruby_buffer_read(&buffer, NULL).data[0] == 31);
    assert(miteruby_buffer_read(&buffer, NULL).data == NULL);
    assert(sigaction(SIGPROF, &previous_action, NULL) == 0);

    assert(pthread_sigmask(SIG_BLOCK, &mask, NULL) == 0);
    assert(miteruby_buffer_try_write(&buffer, NULL, 0, NULL));
    assert(miteruby_buffer_read(&buffer, NULL).data != NULL);
    assert(!miteruby_buffer_try_write(&buffer, NULL, 1, NULL));
    miteruby_buffer_visit(&buffer, visit_empty_record, &mask);
    assert(empty_count == 1);
    assert(pthread_sigmask(SIG_BLOCK, NULL, &current_mask) == 0);
    assert(sigismember(&current_mask, SIGPROF) == 0);
    assert(miteruby_buffer_read(&buffer, NULL).rejected_count == 1);
    miteruby_buffer_visit(&buffer, visit_empty_record, &mask);
    assert(empty_count == 1);

    assert(pthread_sigmask(SIG_SETMASK, &original_mask, NULL) == 0);
    assert(pthread_cond_destroy(&state.condition) == 0);
    assert(pthread_mutex_destroy(&state.mutex) == 0);
    test_interruptible_read();
    miteruby_buffer_close(&buffer, NULL);
    assert(miteruby_buffer_read(&buffer, NULL).end_of_stream);
    miteruby_buffer_destroy(&buffer);
    test_internal_errors();
    alarm(0);
    return ruby_cleanup(0);
}
