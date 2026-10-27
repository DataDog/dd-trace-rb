#pragma once

#include <stddef.h>

// Memory allocator is used as a replacement for libc malloc (or Ruby APIs) for keeping the miteruby state.
//
// By *avoiding Ruby APIs*, we avoid:
// * Triggering more GC cycles than without the profiler
// * Needing to worry about the safety of triggering GC in the middle of profiler work
//
// By *avoiding libc malloc*, we guarantee that:
// * We can't cause fragmentation with our allocations
// * We can't crash due to incorrect allocator state (looking at you, very suspicious jemalloc crash telemetry)
//
// Finally, we get accurate accounting of the memory we use: they show up independently in /proc/pid/maps and
// even get tagged with the name of the allocation on most Linux setups.

// Returns zero-initialized memory, directly backed by mmap (does not rely on libc malloc)
void *miteruby_allocator_alloc(size_t size, const char *name);
void miteruby_allocator_free(void *allocation);
size_t miteruby_allocator_requested_bytes(void);
