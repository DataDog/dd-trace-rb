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
// Guarantees 16-byte alignment; types requiring stricter alignment are unsupported.
void *miteruby_allocator_alloc(size_t size, const char *name);

size_t miteruby_allocator_alloc_size(const void *allocation);
size_t miteruby_allocator_requested_bytes(void);

// DO NOT USE DIRECTLY -- should be used only via `miteruby_allocator_free` to ensure type safety
void miteruby_allocator_free_impl(void **allocation_storage);

// To reduce bugs `miteruby_allocator_free` takes not the pointer returned directly by `miteruby_allocator_alloc`,
// but the address of a variable or field holding the allocation's pointer. Thus the correct usage is:
// ```c
// void *some_mem = miteruby_allocator_alloc(...);
// miteruby_allocator_free(&some_mem); // Frees memory AND sets `some_mem` to `NULL`
// ```
//
// Implementing this in a type-safe way is a bit ugly, so that's what you're about to see:
// Requires &pointer (not NULL); the type check requires the stored value to be a pointer.
// Capture the address once, then free through a real void * temporary and write NULL back through the original type.
// This avoids both repeated evaluation of the argument and aliasing violations from casting typed storage to void **.
#define miteruby_allocator_free(storage) do { \
  __extension__ __auto_type miteruby_allocator_storage_ = (storage); \
  _Static_assert( \
    __builtin_classify_type(*miteruby_allocator_storage_) == __builtin_classify_type((void *)0), \
    "expected the address of a pointer" \
  ); \
  void *miteruby_allocator_allocation_ = *miteruby_allocator_storage_; \
  miteruby_allocator_free_impl(&miteruby_allocator_allocation_); \
  *miteruby_allocator_storage_ = miteruby_allocator_allocation_; \
} while (0)

// Matches Verstable's sized free callback; the allocation header supplies the actual size.
static inline void miteruby_allocator_free_sized(void *allocation, size_t _size) {
  (void) _size;
  miteruby_allocator_free(&allocation);
}
