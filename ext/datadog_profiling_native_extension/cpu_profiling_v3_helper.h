#pragma once

#include <ruby.h>

// VALUE, if non-Qnil, is an exception that should stop the profiler
void cpu_profiling_v3_on_resume(void);
