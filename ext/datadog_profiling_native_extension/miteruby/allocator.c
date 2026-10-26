#include "allocator.h"

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

typedef struct {
  char magic[8];
  uint64_t size;
} allocation_header;

__extension__ _Static_assert(sizeof(allocation_header) == 16, "Miteruby allocation header must be exactly 16 bytes");

void *miteruby_allocator_malloc(size_t size) {
  if (size == 0) {
    errno = EINVAL;
    return NULL;
  }
  if (size > SIZE_MAX - sizeof(allocation_header)) {
    errno = ENOMEM;
    return NULL;
  }

  allocation_header *header = mmap(NULL, size + sizeof(*header), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (header == MAP_FAILED) return NULL;

  memcpy(header->magic, "MITERUBY", sizeof(header->magic));
  header->size = size;
  return header + 1;
}

void miteruby_allocator_free(void *allocation, size_t size) {
  if (allocation == NULL) return;

  allocation_header *header = (allocation_header *)allocation - 1;
  if (memcmp(header->magic, "MITERUBY", sizeof(header->magic)) != 0 ||
      size == 0 || size > SIZE_MAX - sizeof(*header) || header->size != size) abort();

  if (munmap(header, size + sizeof(*header)) != 0) abort();
}
