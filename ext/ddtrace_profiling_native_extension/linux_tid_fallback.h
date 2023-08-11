#pragma once

#include <ruby.h>
#include <pthread.h>

pid_t linux_tid_fallback_for(VALUE linux_tid_fallback, pthread_t thread);
