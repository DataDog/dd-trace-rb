#pragma once

#include <ruby.h>
#include <pthread.h>

pid_t linux_tid_override_for(VALUE linux_tid_override, pthread_t thread);
