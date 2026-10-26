#include "allocator.h"

#include <errno.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#ifdef __linux__
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

void *miteruby_allocator_alloc(size_t size, const char *name) {
  if (size == 0 || name == NULL) {
    errno = EINVAL;
    return NULL;
  }
  if (size > SIZE_MAX - sizeof(allocation_header)) {
    errno = ENOMEM;
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
    // Naming is best-effort, shows up under /proc/pid/maps and may not be supported by current kernel, so we ignore any failures
    (void)prctl(PR_SET_VMA, (unsigned long)PR_SET_VMA_ANON_NAME, header, mapping_size, mapping_name);
  #endif
  return header + 1;
}

void miteruby_allocator_free(void *allocation, size_t size) {
  if (allocation == NULL) return;

  allocation_header *header = (allocation_header *)allocation - 1;
  if (memcmp(header->magic, "MITERUBY", sizeof(header->magic)) != 0 ||
      size == 0 || size > SIZE_MAX - sizeof(*header) || header->size != size) abort();

  if (munmap(header, size + sizeof(*header)) != 0) abort();
  atomic_fetch_sub_explicit(&requested_bytes, size, memory_order_relaxed);
}
