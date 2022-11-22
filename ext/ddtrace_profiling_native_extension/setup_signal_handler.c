#include <ruby.h>
#include <signal.h>
#include <errno.h>

#include "setup_signal_handler.h"

void install_sigprof_signal_handler(void (*signal_handler_function)(int, siginfo_t *, void *), const char *handler_pretty_name) {
  struct sigaction existing_signal_handler_config = {.sa_sigaction = NULL};
  struct sigaction signal_handler_config = {
    .sa_flags = SA_RESTART | SA_SIGINFO,
    .sa_sigaction = signal_handler_function
  };
  sigemptyset(&signal_handler_config.sa_mask);

  if (sigaction(SIGPROF, &signal_handler_config, &existing_signal_handler_config) != 0) {
    rb_exc_raise(rb_syserr_new_str(errno, rb_sprintf("Could not install profiling signal handler (%s)", handler_pretty_name)));
  }

  // In some corner cases (e.g. after a fork), our signal handler may still be around, and that's ok
  if (existing_signal_handler_config.sa_sigaction == signal_handler_function) return;

  if (existing_signal_handler_config.sa_handler != NULL || existing_signal_handler_config.sa_sigaction != NULL) {
    // A previous signal handler already existed. Currently we don't support this situation, so let's just back out
    // of the installation.

    if (sigaction(SIGPROF, &existing_signal_handler_config, NULL) != 0) {
      rb_exc_raise(
        rb_syserr_new_str(
          errno,
          rb_sprintf(
            "Failed to install profiling signal handler (%s): " \
            "While installing a SIGPROF signal handler, the profiler detected that another software/library/gem had " \
            "previously installed a different SIGPROF signal handler. " \
            "The profiler tried to restore the previous SIGPROF signal handler, but this failed. " \
            "The other software/library/gem may have been left in a broken state. ",
            handler_pretty_name
          )
        )
      );
    }

    rb_raise(
      rb_eRuntimeError,
      "Could not install profiling signal handler (%s): There's a pre-existing SIGPROF signal handler",
      handler_pretty_name
    );
  }
}

void remove_sigprof_signal_handler(void) {
  struct sigaction signal_handler_config = {
    .sa_handler = SIG_DFL, // Reset back to default
    .sa_flags = SA_RESTART // TODO: Unclear if this is actually needed/does anything at all
  };
  sigemptyset(&signal_handler_config.sa_mask);

  if (sigaction(SIGPROF, &signal_handler_config, NULL) != 0) rb_sys_fail("Failure while removing the signal handler");
}

void block_sigprof_signal_handler_from_running_in_current_thread(void) {
  sigset_t signals_to_block;
  sigemptyset(&signals_to_block);
  sigaddset(&signals_to_block, SIGPROF);
  pthread_sigmask(SIG_BLOCK, &signals_to_block, NULL);
}
