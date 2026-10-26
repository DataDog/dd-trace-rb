#include "allocator.h"

#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

static void test_allocation(size_t size) {
  unsigned char *allocation = miteruby_allocator_malloc(size);
  assert(allocation != NULL);
  assert((uintptr_t)allocation % 16 == 0);
  assert(memcmp(allocation - 16, "MITERUBY", 8) == 0);
  uint64_t stored_size;
  memcpy(&stored_size, allocation - 8, sizeof(stored_size));
  assert(stored_size == size);

  for (size_t i = 0; i < size; i++) assert(allocation[i] == 0);
  memset(allocation, 0xa5, size);
  for (size_t i = 0; i < size; i++) assert(allocation[i] == 0xa5);
  miteruby_allocator_free(allocation, size);

  unsigned char residency;
  errno = 0;
  assert(mincore(allocation - 16, 1, (void *)&residency) == -1);
  assert(errno == ENOMEM);
}

static void corrupt_magic(void) {
  unsigned char *allocation = miteruby_allocator_malloc(32);
  assert(allocation != NULL);
  allocation[-16] = 'X';
  miteruby_allocator_free(allocation, 32);
}

static void corrupt_size(void) {
  unsigned char *allocation = miteruby_allocator_malloc(32);
  assert(allocation != NULL);
  memset(allocation - 8, 0, 8);
  miteruby_allocator_free(allocation, 32);
}

static void wrong_size(void) {
  void *allocation = miteruby_allocator_malloc(32);
  assert(allocation != NULL);
  miteruby_allocator_free(allocation, 31);
}

static void expect_abort(void (*test)(void)) {
  pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    test();
    _exit(0);
  }
  int status;
  assert(waitpid(child, &status, 0) == child);
  assert(WIFSIGNALED(status));
  assert(WTERMSIG(status) == SIGABRT);
}

int main(void) {
  struct rlimit core_limit = {0, 0};
  assert(setrlimit(RLIMIT_CORE, &core_limit) == 0);

  long page_size = sysconf(_SC_PAGESIZE);
  assert(page_size > 16);
  const size_t sizes[] = {1, 16, 32, (size_t)page_size - 16, (size_t)page_size - 15, (size_t)page_size, (size_t)page_size * 3};
  for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) test_allocation(sizes[i]);

  errno = 0;
  assert(miteruby_allocator_malloc(0) == NULL);
  assert(errno == EINVAL);
  errno = 0;
  assert(miteruby_allocator_malloc(SIZE_MAX) == NULL);
  assert(errno == ENOMEM);
  miteruby_allocator_free(NULL, 0);

  expect_abort(corrupt_magic);
  expect_abort(corrupt_size);
  expect_abort(wrong_size);
  return 0;
}
