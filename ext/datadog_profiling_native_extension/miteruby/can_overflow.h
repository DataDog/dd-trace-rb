#pragma once

#include <stdbool.h>
#include <stddef.h>

// Call once before sampling starts. If probing is unavailable, miteruby_can_overflow returns false.
bool miteruby_init_can_overflow(void);

// Assumes a downward-growing stack with a guard page, as used by pthreads and Ruby fibers.
// The caller must keep the budgeted allocations in a separate, non-inlined function.
MITERUBY_INTERNAL bool miteruby_can_overflow(size_t stack_bytes);
