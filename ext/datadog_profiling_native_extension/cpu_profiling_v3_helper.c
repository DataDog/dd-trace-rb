#include "cpu_profiling_v3_helper.h"
#include "ruby_helpers.h"

#include <signal.h>
#include <time.h>
#include <stdbool.h>

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
