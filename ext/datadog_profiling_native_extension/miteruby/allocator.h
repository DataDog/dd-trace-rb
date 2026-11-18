#pragma once

#include <stddef.h>

// The miteruby allocator is used as a replacement for libc malloc (or Ruby APIs) for keeping the miteruby state.
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

// Returns zero-initialized memory, directly backed by mmap (does not rely on libc malloc).
// Guarantees 16-byte alignment (mmap guarantees it). types requiring stricter alignment are unsupported.
//
// Allocating memory in this way is slower than malloc, so this is intended for big chunks that
// will back arenas/pools/large buffers and happen **rarely**, not small linked list nodes that
// get allocated/deallocated all the time.
//
// Note: The allocator adds a header to every allocation, which means the size requested to the OS is bigger than
// the `size` argument (e.g. alloc(4096) will allocate 2 pages not 1 if that's the system page size).
void *miteruby_allocator_alloc(size_t size, const char *name);

size_t miteruby_allocator_alloc_size(const void *allocation);

// Returns the total bytes that were allocated from the OS and not yet released with free, for statistics.
//
// Note 1: This is "allocated bytes" and not in-use bytes because memory pages in the range returned by our allocator
//         are only page faulted lazily by the OS when accessed.
//         Thus for instance on our arrays, as long as we read/write sequentially from the beginning, if we don't
//         fill them, we may never need resident memory backing the whole range.
// Note 2: This is rounded up to page size, and includes the header added by the allocator.
//
// => Thus in practice this value is an upper bound on the resident memory backing the allocator.
size_t miteruby_allocator_currently_allocated_bytes_stat(void);

void miteruby_allocator_free(void *allocation);

// Matches Verstable's sized free callback; the allocation header supplies the actual size.
static inline void miteruby_allocator_free_sized(void *allocation, size_t _size) {
  (void) _size;
  miteruby_allocator_free(allocation);
}
