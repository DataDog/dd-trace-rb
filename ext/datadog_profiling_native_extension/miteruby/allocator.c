#include "allocator.h"

#include <errno.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#ifdef __linux__
  // For naming the allocation with prctl
  #include <sys/prctl.h>

  #ifndef PR_SET_VMA
    #define PR_SET_VMA 0x53564d41
    #define PR_SET_VMA_ANON_NAME 0
  #endif
#endif

typedef struct {
  char magic[8];
  uint64_t size;
} allocation_header;

__extension__ _Static_assert(sizeof(allocation_header) == 16, "Miteruby allocation header must be exactly 16 bytes");

static atomic_size_t requested_bytes = 0;

size_t miteruby_allocator_requested_bytes(void) {
  return atomic_load_explicit(&requested_bytes, memory_order_relaxed);
}

// Allocates space for `size` bytes.
//
// We allocate a bit of extra space at the beginning of the allocation to place the `allocation_header` so we can identify our own
// allocations.
void *miteruby_allocator_alloc(size_t size, const char *name) {
  if (size == 0 || name == NULL || size > SIZE_MAX - sizeof(allocation_header)) {
    errno = EINVAL;
    return NULL;
  }

  size_t mapping_size = size + sizeof(allocation_header);
  char mapping_name[80];
  snprintf(mapping_name, sizeof(mapping_name), "miteruby.%s", name);

  allocation_header *header = mmap(NULL, mapping_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (header == MAP_FAILED) return NULL;

  memcpy(header->magic, "MITERUBY", sizeof(header->magic));
  header->size = size;

  atomic_fetch_add_explicit(&requested_bytes, size, memory_order_relaxed);

  #ifdef __linux__
    // Try to name the allocation (shows up under /proc/pid/maps).
    // Not all Linux kernels support this feature (it's optional), so we ignore any failures.
    (void) prctl(PR_SET_VMA, (unsigned long) PR_SET_VMA_ANON_NAME, header, mapping_size, mapping_name);
  #endif

  return header + 1; // Return pointer to memory just after the header
}

void miteruby_allocator_free(void *allocation) {
  if (allocation == NULL) return;

  // Find header before allocation pointer
  allocation_header *header = (allocation_header *)allocation - 1;

  if (memcmp(header->magic, "MITERUBY", sizeof(header->magic)) != 0) abort();

  size_t size = header->size;
  if (munmap(header, size + sizeof(allocation_header)) != 0) abort();

  atomic_fetch_sub_explicit(&requested_bytes, size, memory_order_relaxed);
}
