#pragma once

#include <stddef.h>

// Simple memory allocator, directly backed by mmap (does not rely on libc malloc)
void *miteruby_allocator_malloc(size_t size);
void miteruby_allocator_free(void *allocation, size_t size);
size_t miteruby_allocator_requested_bytes(void);
