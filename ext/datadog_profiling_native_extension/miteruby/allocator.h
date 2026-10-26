#pragma once

#include <stddef.h>

// Returns zero-initialized memory, directly backed by mmap (does not rely on libc malloc)
// Naming is only used in Linux (best-effort, shows up under /proc/pid/maps)
void *miteruby_allocator_alloc(size_t size, const char *name);
void miteruby_allocator_free(void *allocation, size_t size);
size_t miteruby_allocator_requested_bytes(void);
