#include "allocator.h"
#include "../helpers.h"

#include <ruby.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// In practice, we don't expect our profiler to do more than this in a single allocation -- we'd be adding
// a lot of memory overhead to an app if we did! This can be raised in the future but I'd advise really thinking
// through why in production we'd need such usage.
#define ALLOC_MAXIMUM_BYTES MiB_AS_BYTES(100)

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

static size_t system_page_size = 4096;
static atomic_size_t currently_allocated_bytes_stat = 0;

__attribute__((constructor)) static void initialize_system_page_size(void) {
  long page_size = sysconf(_SC_PAGESIZE);
  if (page_size > (long)system_page_size) {
    system_page_size = (size_t)page_size;
  }
}

static size_t allocation_mapping_size(size_t size) {
  return size + sizeof(allocation_header);
}

static size_t rounded_to_page_size(size_t mapping_size) {
  return ((mapping_size + system_page_size - 1) / system_page_size) * system_page_size;
}

size_t miteruby_allocator_currently_allocated_bytes_stat(void) {
  return atomic_load_explicit(&currently_allocated_bytes_stat, memory_order_relaxed);
}

// Allocates space for `size` bytes.
//
// We allocate a bit of extra space at the beginning of the allocation to place the `allocation_header` so we can identify our own
// allocations.
void *miteruby_allocator_alloc(size_t size, const char *name) {
  if (size == 0 || name == NULL || size > ALLOC_MAXIMUM_BYTES) {
    errno = EINVAL;
    return NULL;
  }

  size_t mapping_size = allocation_mapping_size(size);

  allocation_header *header = mmap(NULL, mapping_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (header == MAP_FAILED) return NULL;

  memcpy(header->magic, "MITERUBY", sizeof(header->magic));
  header->size = size;

  atomic_fetch_add_explicit(&currently_allocated_bytes_stat, rounded_to_page_size(mapping_size), memory_order_relaxed);

  #ifdef __linux__
    // Try to name the allocation (shows up under /proc/pid/maps).
    // Not all Linux kernels support this feature (it's optional), so we ignore any failures.
    char mapping_name[80] = "miteruby.";
    size_t prefix_size = sizeof("miteruby.") - 1;
    size_t name_size = strnlen(name, sizeof(mapping_name) - prefix_size - 1);
    memcpy(mapping_name + prefix_size, name, name_size);
    mapping_name[prefix_size + name_size] = '\0';

    (void) prctl(PR_SET_VMA, (unsigned long) PR_SET_VMA_ANON_NAME, header, mapping_size, mapping_name);
  #endif

  return header + 1; // Return pointer to memory just after the header
}

size_t miteruby_allocator_alloc_size(const void *allocation) {
  if (allocation == NULL) return 0;

  const allocation_header *header = (const allocation_header *)allocation - 1;
  if (memcmp(header->magic, "MITERUBY", sizeof(header->magic)) != 0)
    rb_bug("Invalid miteruby allocation header at %p", (void *) header);

  return header->size;
}

void miteruby_allocator_free_impl(void **allocation_storage) {
  void *allocation = *allocation_storage;
  if (allocation == NULL) return;

  size_t size = miteruby_allocator_alloc_size(allocation);
  allocation_header *header = (allocation_header *)allocation - 1;
  size_t mapping_size = allocation_mapping_size(size);
  *allocation_storage = NULL;
  if (munmap(header, mapping_size) != 0) {
    // ENOMEM can occur when splitting a VMA; keep the mapping counted and let the application continue.
    if (errno == ENOMEM) return;
    rb_bug("Failed to unmap miteruby mapping at %p (mapping_size=%zu, errno=%d)", (void *) header, mapping_size, errno);
  }

  atomic_fetch_sub_explicit(&currently_allocated_bytes_stat, rounded_to_page_size(mapping_size), memory_order_relaxed);
}
