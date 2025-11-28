#pragma once

#include <signal.h>
#include "datadog_ruby_common.h"

typedef enum {
  SIGNAL_HANDLER_NAME_NULL, // Reserved to avoid accidental 0-value usage
  SIGNAL_HANDLER_NAME_handle_sampling_signal,
  SIGNAL_HANDLER_NAME_testing_signal_handler,
  SIGNAL_HANDLER_NAME_holding_the_gvl_signal_handler,
  SIGNAL_HANDLER_NAME_empty_signal_handler,
  SIGNAL_HANDLER_NAME_COUNT
} signal_handler_name_t;

static const char *const SIGNAL_HANDLER_NAMES[SIGNAL_HANDLER_NAME_COUNT] = {
  [SIGNAL_HANDLER_NAME_NULL] = "", // Unused
  [SIGNAL_HANDLER_NAME_handle_sampling_signal] = "handle_sampling_signal",
  [SIGNAL_HANDLER_NAME_testing_signal_handler] = "testing_signal_handler",
  [SIGNAL_HANDLER_NAME_holding_the_gvl_signal_handler] = "holding_the_gvl_signal_handler",
  [SIGNAL_HANDLER_NAME_empty_signal_handler] = "empty_signal_handler"
};

#define SIGNAL_HANDLER_NAME(var) SIGNAL_HANDLER_NAME_##var

void empty_signal_handler(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext);
#define install_sigprof_signal_handler(signal_handler_function) \
  private_install_sigprof_signal_handler(signal_handler_function, SIGNAL_HANDLER_NAME(signal_handler_function))
void private_install_sigprof_signal_handler(void (*signal_handler_function)(int, siginfo_t *, void *), signal_handler_name_t handler_pretty_name);
void replace_sigprof_signal_handler_with_empty_handler(void (*expected_existing_handler)(int, siginfo_t *, void *));
void remove_sigprof_signal_handler(void);
void block_sigprof_signal_handler_from_running_in_current_thread(void);
void unblock_sigprof_signal_handler_from_running_in_current_thread(void);
VALUE is_sigprof_blocked_in_current_thread(void);
