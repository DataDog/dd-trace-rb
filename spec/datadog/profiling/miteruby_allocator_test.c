#include "allocator.h"

#include <assert.h>
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __linux__
static void test_mapping_name(const char *name, const char *expected_name) {
  void *allocation = miteruby_allocator_alloc(32, name);
  assert(allocation != NULL);

  FILE *maps = fopen("/proc/self/maps", "r");
  assert(maps != NULL);
  char line[1024];
  int found = 0;
  while (fgets(line, sizeof(line), maps) != NULL) {
    uintptr_t start, end;
    if (sscanf(line, "%" SCNxPTR "-%" SCNxPTR, &start, &end) == 2 &&
        (uintptr_t)allocation >= start && (uintptr_t)allocation < end) {
      assert(strstr(line, expected_name) != NULL);
      found = 1;
      break;
    }
  }
  assert(fclose(maps) == 0);
  assert(found);
  miteruby_allocator_free(allocation, 32);
}
#endif

static void test_allocation(size_t size) {
  size_t before = miteruby_allocator_requested_bytes();
  unsigned char *allocation = miteruby_allocator_alloc(size, "test");
  assert(allocation != NULL);
  assert(miteruby_allocator_requested_bytes() == before + size);
  assert((uintptr_t)allocation % 16 == 0);
  assert(memcmp(allocation - 16, "MITERUBY", 8) == 0);
  uint64_t stored_size;
  memcpy(&stored_size, allocation - 8, sizeof(stored_size));
  assert(stored_size == size);

  for (size_t i = 0; i < size; i++) assert(allocation[i] == 0);
  memset(allocation, 0xa5, size);
  for (size_t i = 0; i < size; i++) assert(allocation[i] == 0xa5);
  miteruby_allocator_free(allocation, size);
  assert(miteruby_allocator_requested_bytes() == before);

  unsigned char residency;
  errno = 0;
  assert(mincore(allocation - 16, 1, (void *)&residency) == -1);
  assert(errno == ENOMEM);
}

static void test_accounting(void) {
  void *first = miteruby_allocator_alloc(17, "test");
  void *second = miteruby_allocator_alloc(1000, "test");
  assert(first != NULL && second != NULL);
  assert(miteruby_allocator_requested_bytes() == 1017);
  assert(miteruby_allocator_alloc(0, "test") == NULL);
  assert(miteruby_allocator_alloc(SIZE_MAX, "test") == NULL);
  assert(miteruby_allocator_alloc(32, NULL) == NULL);
  miteruby_allocator_free(NULL, 0);
  assert(miteruby_allocator_requested_bytes() == 1017);
  miteruby_allocator_free(first, 17);
  assert(miteruby_allocator_requested_bytes() == 1000);
  miteruby_allocator_free(second, 1000);
  assert(miteruby_allocator_requested_bytes() == 0);
}

typedef struct {
  void *allocations[64];
} thread_allocations;

static void *allocate_in_thread(void *arg) {
  thread_allocations *state = arg;
  for (size_t i = 0; i < 64; i++) {
    state->allocations[i] = miteruby_allocator_alloc(32, "test");
    assert(state->allocations[i] != NULL);
  }
  return NULL;
}

static void *free_in_thread(void *arg) {
  thread_allocations *state = arg;
  for (size_t i = 0; i < 64; i++) miteruby_allocator_free(state->allocations[i], 32);
  return NULL;
}

static void test_concurrent_accounting(void) {
  pthread_t threads[4];
  thread_allocations states[4];
  for (size_t i = 0; i < 4; i++) assert(pthread_create(&threads[i], NULL, allocate_in_thread, &states[i]) == 0);
  for (size_t i = 0; i < 4; i++) assert(pthread_join(threads[i], NULL) == 0);
  assert(miteruby_allocator_requested_bytes() == 4 * 64 * 32);
  for (size_t i = 0; i < 4; i++) assert(pthread_create(&threads[i], NULL, free_in_thread, &states[i]) == 0);
  for (size_t i = 0; i < 4; i++) assert(pthread_join(threads[i], NULL) == 0);
  assert(miteruby_allocator_requested_bytes() == 0);
}

static void corrupt_magic(void) {
  unsigned char *allocation = miteruby_allocator_alloc(32, "test");
  assert(allocation != NULL);
  allocation[-16] = 'X';
  miteruby_allocator_free(allocation, 32);
}

static void corrupt_size(void) {
  unsigned char *allocation = miteruby_allocator_alloc(32, "test");
  assert(allocation != NULL);
  memset(allocation - 8, 0, 8);
  miteruby_allocator_free(allocation, 32);
}

static void wrong_size(void) {
  void *allocation = miteruby_allocator_alloc(32, "test");
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
  assert(miteruby_allocator_requested_bytes() == 0);
  struct rlimit core_limit = {0, 0};
  assert(setrlimit(RLIMIT_CORE, &core_limit) == 0);

  long page_size = sysconf(_SC_PAGESIZE);
  assert(page_size > 16);
  const size_t sizes[] = {1, 16, 32, (size_t)page_size - 16, (size_t)page_size - 15, (size_t)page_size, (size_t)page_size * 3};
  for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) test_allocation(sizes[i]);

  errno = 0;
  assert(miteruby_allocator_alloc(0, "test") == NULL);
  assert(errno == EINVAL);
  errno = 0;
  assert(miteruby_allocator_alloc(SIZE_MAX, "test") == NULL);
  assert(errno == ENOMEM);
  miteruby_allocator_free(NULL, 0);

  test_accounting();
  test_concurrent_accounting();

#ifdef __linux__
  test_mapping_name("named_allocation", "[anon:miteruby.named_allocation]");
  char long_name[100];
  memset(long_name, 'a', sizeof(long_name) - 1);
  long_name[sizeof(long_name) - 1] = '\0';
  char expected_name[87];
  snprintf(expected_name, sizeof(expected_name), "[anon:miteruby.%.70s]", long_name);
  test_mapping_name(long_name, expected_name);
#endif

  expect_abort(corrupt_magic);
  expect_abort(corrupt_size);
  expect_abort(wrong_size);
  return 0;
}
