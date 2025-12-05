#pragma once

#include <ruby.h>

void cpu_profiling_v3_init(void);
void cpu_profiling_v3_on_resume(void);
void cpu_profiling_v3_on_suspend(void);
void cpu_profiling_v3_enable_timer_cleanup(void);
