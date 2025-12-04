#include <ruby.h>
#include <ruby/thread.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <stdbool.h>

#include "datadog_ruby_common.h"
#include "cpu_profiling_v3_helper.h"

typedef struct {
  bool valid;
  bool failed;
  timer_t timer;
} per_thread_cpu_timer;

static __thread per_thread_cpu_timer current_thread_timer;

static void initialize_current_thread_cpu_timer(void) {
  struct sigevent config = {
    .sigev_notify = SIGEV_THREAD_ID,
    .sigev_signo = SIGPROF,
    // Manpage calls this `sigev_notify_thread_id` ( https://manpages.opensuse.org/Tumbleweed/man-pages/sigevent.3type.en.html )
    // but the glibc definition is... different?
    ._sigev_un._tid = gettid(),
  };

  int error = timer_create(CLOCK_PROCESS_CPUTIME_ID, &config, &current_thread_timer.timer);

  if (error == 0) {
    current_thread_timer.valid = true;
  } else {
    current_thread_timer.failed = true;
    // TODO: Better logging
    fprintf(stderr, "Failure to create CPU timer %s:%d:in `%s': %s\n",  __FILE__, __LINE__, __func__, strerror(errno));
  }
}

void cpu_profiling_v3_on_resume(void) {
  if (!current_thread_timer.valid && !current_thread_timer.failed) {
    initialize_current_thread_cpu_timer();
    if (!current_thread_timer.valid) return;
  }

  // TODO
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
