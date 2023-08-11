#include "linux_tid_from_pthread.h"
#include "helpers.h"

short setup_linux_tid_from_pthread_offset(void) { return -1; }
pid_t linux_tid_from(DDTRACE_UNUSED pthread_t thread, DDTRACE_UNUSED short offset) { return -1; }
