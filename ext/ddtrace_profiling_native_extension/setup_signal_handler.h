#pragma once

void install_sigprof_signal_handler(void (*signal_handler_function)(int, siginfo_t *, void *));
void remove_sigprof_signal_handler(void);
void block_sigprof_signal_handler_from_running_in_current_thread(void);
