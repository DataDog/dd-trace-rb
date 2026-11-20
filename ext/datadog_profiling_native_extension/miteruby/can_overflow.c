#define _GNU_SOURCE
#include "can_overflow.h"

#include <stdint.h>
#include <sys/mman.h>
#include <unistd.h>

#if defined(__APPLE__)
  #define STACK_ADVICE POSIX_MADV_WILLNEED
#elif defined(__linux__)
  #ifndef MADV_POPULATE_WRITE
    #define MADV_POPULATE_WRITE 23
  #endif
  #define STACK_ADVICE MADV_POPULATE_WRITE
#else
  #error "The stack probe requires Linux or macOS"
#endif

static size_t system_page_size = 0;

bool miteruby_init_can_overflow(void) {
#if defined(__APPLE__)
  // Before macOS 15.4, MADV_WILLNEED skipped unreadable mappings, including PROT_NONE stack guards.
  // https://github.com/apple-oss-distributions/xnu/blob/xnu-11215.81.4/osfmk/vm/vm_map.c#L16517-L16525 (macOS 15.3)
  // In macOS 15.4, XNU requests a read fault for PROT_NONE pages and propagates protection errors.
  // https://github.com/apple-oss-distributions/xnu/blob/xnu-11417.101.15/osfmk/vm/vm_map.c#L16678-L16708
  if (!__builtin_available(macOS 15.4, *)) return false;
#endif
  long configured_page_size = sysconf(_SC_PAGESIZE);
  if (configured_page_size <= 0) return false;
  size_t page_size = (size_t) configured_page_size;
  uintptr_t page = (uintptr_t) &page_size & -page_size;
  if (posix_madvise((void *) page, page_size, STACK_ADVICE) != 0) return false;
  system_page_size = page_size;
  return true;
}

__attribute__((noinline)) bool miteruby_can_overflow(size_t stack_bytes) {
  if (system_page_size == 0) return false;

  // This needs noinline because inlining would give us the caller's frame pointer.
  uintptr_t frame = (uintptr_t) __builtin_frame_address(0);
  if (stack_bytes > frame) return true;
  uintptr_t start = (frame - stack_bytes) & -system_page_size;
  return posix_madvise((void *) start, frame - start, STACK_ADVICE) != 0;
}
