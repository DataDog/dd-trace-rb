#define _GNU_SOURCE 1
#define MITERUBY_INTERNAL static
#include "../../../ext/datadog_profiling_native_extension/miteruby/can_overflow.c"

#undef NDEBUG
#include <assert.h>
#include <pthread.h>
#include <stdint.h>

#define THREAD_STACK_SIZE (512 * 1024)

static void *check_guarded_stack(void *unused) {
  (void) unused;
  assert(!miteruby_can_overflow(8 * 1024));
  assert(miteruby_can_overflow(THREAD_STACK_SIZE));
  return NULL;
}

int main(void) {
  assert(!miteruby_can_overflow(SIZE_MAX));
  if (!miteruby_init_can_overflow()) {
    assert(!miteruby_can_overflow(SIZE_MAX));
    return 0;
  }
  assert(miteruby_can_overflow(SIZE_MAX));

  pthread_attr_t attr;
  pthread_t thread;
  assert(pthread_attr_init(&attr) == 0);
  assert(pthread_attr_setstacksize(&attr, THREAD_STACK_SIZE) == 0);
  assert(pthread_create(&thread, &attr, check_guarded_stack, NULL) == 0);
  assert(pthread_attr_destroy(&attr) == 0);
  assert(pthread_join(thread, NULL) == 0);
  return 0;
}
