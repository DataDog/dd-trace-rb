#include <ruby.h>
#include <ruby/thread.h>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <stdbool.h>

#include "datadog_ruby_common.h"
#include "cpu_profiling_v3_helper.h"
#include "time_helpers.h"
typedef struct {
  bool valid;
  bool failed; // Once set, we'll never try to use the timer for this thread again
  timer_t timer;
  // Whenever we disarm the timer, we keep here "how far we were from the next sample". This makes sure that we correctly account for
  // CPU time spent across a disarm/arm cycle (otherwise if we started always from the interval we'd be throwing CPU time away)
  struct timespec last_suspend_leftover_time;
  bool is_armed; // TODO: valid/failed/is_armed smells of state machine. Do we want to make it a bit more explicit?
} per_thread_cpu_timer_state;

static __thread per_thread_cpu_timer_state current_thread_timer;

static const struct timespec CPU_TIMER_DEFAULT_INTERVAL = {.tv_nsec = MILLIS_AS_NS(10)};

static rb_internal_thread_specific_key_t cpu_time_at_suspend_key;

void cpu_profiling_v3_init(void) {
  cpu_time_at_suspend_key = rb_internal_thread_specific_key_create();
}

// TODO: According to the https://manpages.opensuse.org/Tumbleweed/man-pages/timer_create.2.en.html manpage, the first argument to
// `timer_create` "can be specified as the clockid returned by a call to clock_getcpuclockid(3) or pthread_getcpuclockid(3)".
//
// This means that we don't necessarily need to create the timer on the thread it refers to... Which may lead to some code
// simplifications. To be explored later?
static void initialize_current_thread_cpu_timer(void) {
  struct sigevent config = {
    .sigev_notify = SIGEV_THREAD_ID,
    .sigev_signo = SIGPROF,
    // Manpage calls this `sigev_notify_thread_id` ( https://manpages.opensuse.org/Tumbleweed/man-pages/sigevent.3type.en.html )
    // but the glibc definition is... different?
    ._sigev_un._tid = gettid(),
    .sigev_value.sival_int = 1234, // WIP
  };

  timer_t new_timer;
  int error = timer_create(CLOCK_PROCESS_CPUTIME_ID, &config, &new_timer);

  if (error == 0) {
    // Fully reinitialize the state, to make sure there's no leftover counters
    current_thread_timer = (per_thread_cpu_timer_state) {
      .valid = true,
      .failed = false,
      .timer = new_timer,
      .last_suspend_leftover_time = CPU_TIMER_DEFAULT_INTERVAL,
      .is_armed = false,
    };
  } else {
    current_thread_timer.failed = true;
    // TODO: Better logging
    fprintf(stderr, "Failure to create CPU timer %s:%d:in `%s': %s\n",  __FILE__, __LINE__, __func__, strerror(errno));
  }
}

// TODO: Right now this assumes CPU Profiling 3.0 is always enabled
void cpu_profiling_v3_on_resume(void) {
  if (!current_thread_timer.valid && !current_thread_timer.failed) {
    initialize_current_thread_cpu_timer();
    if (!current_thread_timer.valid) return;
  }

  if (current_thread_timer.is_armed) {
    // TODO: Think a bit more about what to do here
    fprintf(stderr, "CPU timer on thread %d was already armed\n", gettid());
    return;
  }

  // Let's arm the timer
  struct itimerspec timer_config = {
    .it_interval = CPU_TIMER_DEFAULT_INTERVAL,
    .it_value = current_thread_timer.last_suspend_leftover_time,
  };
  int error = timer_settime(current_thread_timer.timer, 0, &timer_config, NULL);
  if (error != 0) {
    // TODO: Better logging
    fprintf(stderr, "Failure to set CPU timer on thread %d %s:%d:in `%s': %s\n",  gettid(), __FILE__, __LINE__, __func__, strerror(errno));
  } else {
    current_thread_timer.is_armed = true;
  }
}

void cpu_profiling_v3_on_suspend(void) {
  if (!current_thread_timer.valid) return;

  if (!current_thread_timer.is_armed) {
    // TODO: I suspect this can actually happen sometimes -- I left a comment on gvl-tracing that indicated multiple
    // suspends can show up for a Ruby thread in a row, and we're calling this code based also on SUSPEND.
    // (TODO: We could make it an error based on some argument -- have the caller tell us if it's ok to double-suspend or not,
    // since we know for which callers this would be expected to happen or not)
    fprintf(stderr, "CPU timer on thread %d was not armed\n", gettid());
    return;
  }

  // Let's disarm the timer
  struct itimerspec disable_timer = { 0 };
  struct itimerspec timer_state;

  int error = timer_settime(current_thread_timer.timer, 0, &disable_timer, &timer_state);
  if (error != 0) {
    // TODO: Better logging
    fprintf(stderr, "Failure to disarm CPU timer on thread %d %s:%d:in `%s': %s\n",  gettid(), __FILE__, __LINE__, __func__, strerror(errno));
  }

  if (timer_state.it_value.tv_sec != 0 || timer_state.it_value.tv_nsec != 0) {
    current_thread_timer.last_suspend_leftover_time = timer_state.it_value;
  }

  if (timer_state.it_interval.tv_sec == 0 && timer_state.it_interval.tv_nsec == 0) {
    fprintf(stderr, "CPU timer on thread %d was disabled but is_armed was true\n", gettid());
  }

  current_thread_timer.is_armed = false;
}

static void on_thread_exit_cleanup_timer(
  DDTRACE_UNUSED rb_event_flag_t _unused1,
  DDTRACE_UNUSED const rb_internal_thread_event_data_t *_unused2,
  DDTRACE_UNUSED void *_unused3
) {
  if (current_thread_timer.valid) {
    int error = timer_delete(current_thread_timer.timer);
    if (error != 0) {
      // TODO: Better logging
      fprintf(stderr, "Failure to delete CPU timer %s:%d:in `%s': %s\n",  __FILE__, __LINE__, __func__, strerror(errno));
    }
    current_thread_timer.valid = false;
  }
}

void cpu_profiling_v3_enable_timer_cleanup(void) {
  rb_internal_thread_add_event_hook(on_thread_exit_cleanup_timer, RUBY_INTERNAL_THREAD_EVENT_EXITED, NULL);
}
