#ifndef _GNU_SOURCE
  #define _GNU_SOURCE 1
#endif
#include <dlfcn.h>
#include <ruby.h>
#include <stdbool.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.h"

#undef NDEBUG
#include <assert.h>

static size_t lookup_count;
static size_t allocation_failures;
static bool fail_allocations;
static const char extension_path[] = "/extensions/test.so";
static const char ruby_path[] = "/lib/libruby.so";

static int test_dladdr(const void *function, Dl_info *info) {
  lookup_count++;
  if (function == (void *) 1) return 0;
  info->dli_fname = function == (void *) rb_ary_new ? ruby_path : extension_path;
  if (function == (void *) 2) info->dli_fname = NULL;
  return 1;
}

static void *test_alloc(size_t size, const char *name) {
  if (fail_allocations) {
    allocation_failures++;
    return NULL;
  }
  return miteruby_allocator_alloc(size, name);
}

#define dladdr test_dladdr
#define miteruby_allocator_alloc test_alloc
#include "../../../ext/datadog_profiling_native_extension/native_filenames.c"
#undef miteruby_allocator_alloc
#undef dladdr

static void test_hits_and_misses(void) {
  native_filenames_cache cache;
  native_filenames_cache_init(&cache);
  lookup_count = 0;

  for (size_t i = 0; i < 2; i++) {
    native_filename found = native_filenames_lookup(&cache, (native_function_pointer) 3);
    assert(found.path == extension_path);
    assert(!found.is_ruby);
    for (uintptr_t missing = 1; missing <= 2; missing++) {
      native_filename absent = native_filenames_lookup(&cache, (native_function_pointer) missing);
      assert(strcmp(absent.path, "") == 0);
      assert(!absent.is_ruby);
    }
  }

  assert(lookup_count == 3);
  assert(native_filenames_cache_size(&cache) == 3);
  native_filenames_cache_cleanup(&cache);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
}

static void test_capacity(void) {
  native_filenames_cache cache;
  native_filenames_cache_init(&cache);
  for (uintptr_t i = 1; i <= 117964; i++) {
    native_filenames_lookup(&cache, (native_function_pointer) i);
  }
  assert(native_filenames_cache_size(&cache) == 117964);
  assert(native_filenames_cache_bucket_count(&cache) == 131072);
  assert(miteruby_allocator_alloc_size(cache.buckets) <= NATIVE_FILENAMES_MAX_BYTES);
  void *buckets = cache.buckets;
  size_t before = lookup_count;
  native_filenames_lookup(&cache, (native_function_pointer) 1);
  assert(lookup_count == before);
  assert(native_filenames_cache_size(&cache) == 117964);

  native_filename found = native_filenames_lookup(&cache, (native_function_pointer) 117965);
  assert(found.path == extension_path);
  assert(native_filenames_cache_size(&cache) == 1);
  assert(cache.buckets == buckets);
  native_filenames_lookup(&cache, (native_function_pointer) 117965);
  assert(lookup_count == before + 1);
  native_filenames_lookup(&cache, (native_function_pointer) 1);
  assert(lookup_count == before + 2);
  native_filenames_cache_cleanup(&cache);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
}

static void test_allocation_failure(void) {
  native_filenames_cache cache;
  native_filenames_cache_init(&cache);
  fail_allocations = true;
  assert(native_filenames_lookup(&cache, (native_function_pointer) 3).path == extension_path);
  assert(native_filenames_cache_size(&cache) == 0);
  assert(allocation_failures > 0);

  fail_allocations = false;
  native_filenames_lookup(&cache, (native_function_pointer) 1);
  native_filenames_lookup(&cache, (native_function_pointer) 3);
  size_t before = allocation_failures;
  fail_allocations = true;
  uintptr_t key;
  for (key = 4; key < 100; key++) {
    assert(native_filenames_lookup(&cache, (native_function_pointer) key).path == extension_path);
    if (allocation_failures > before) break;
  }
  assert(allocation_failures > before);
  assert(native_filenames_cache_size(&cache) == 1);
  size_t lookups_before = lookup_count;
  assert(native_filenames_lookup(&cache, (native_function_pointer) key).path == extension_path);
  assert(lookup_count == lookups_before);
  assert(strcmp(native_filenames_lookup(&cache, (native_function_pointer) 1).path, "") == 0);
  assert(lookup_count == lookups_before + 1);

  fail_allocations = false;
  native_filenames_lookup(&cache, (native_function_pointer) 100);
  lookups_before = lookup_count;
  native_filenames_lookup(&cache, (native_function_pointer) 100);
  assert(lookup_count == lookups_before);
  native_filenames_cache_cleanup(&cache);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
}

static void test_fork(void) {
  native_filenames_cache cache;
  native_filenames_cache_init(&cache);
  native_filenames_lookup(&cache, (native_function_pointer) 3);
  size_t before = lookup_count;
  pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    assert(native_filenames_lookup(&cache, (native_function_pointer) 3).path == extension_path);
    assert(lookup_count == before);
    assert(native_filenames_lookup(&cache, (native_function_pointer) 4).path == extension_path);
    native_filenames_cache_cleanup(&cache);
    assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
    _exit(0);
  }
  int status;
  assert(waitpid(child, &status, 0) == child);
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
  assert(native_filenames_cache_size(&cache) == 1);
  assert(native_filenames_lookup(&cache, (native_function_pointer) 3).path == extension_path);
  assert(lookup_count == before);
  native_filenames_cache_cleanup(&cache);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
}

static void test_ruby_filenames(void) {
  VALUE profiling = rb_define_module("NativeFilenamesTest");
  rb_define_const(profiling, "STATIC_RUBY_PATH", Qnil);
  native_filenames_init(profiling);
  native_filenames_cache cache;
  native_filenames_cache_init(&cache);
  native_filename filename = native_filenames_lookup(&cache, (native_function_pointer) rb_ary_new);
  assert(filename.is_ruby);
  assert(filename.path == ruby_path);

  rb_const_remove(profiling, rb_intern("STATIC_RUBY_PATH"));
  rb_define_const(profiling, "STATIC_RUBY_PATH", rb_str_new_cstr("/actual/ruby"));
  native_filenames_init(profiling);
  rb_gc_start();
  filename = native_filenames_lookup(&cache, (native_function_pointer) rb_ary_new);
  assert(filename.is_ruby);
  assert(strcmp(filename.path, "/actual/ruby") == 0);
  assert(native_filenames_lookup(&cache, (native_function_pointer) 3).path == extension_path);
  native_filenames_cache_cleanup(&cache);
  assert(miteruby_allocator_currently_allocated_bytes_stat() == 0);
}

int main(int argc, char **argv) {
  ruby_sysinit(&argc, &argv);
  RUBY_INIT_STACK;
  ruby_init();

  test_hits_and_misses();
  test_capacity();
  test_allocation_failure();
  test_fork();
  test_ruby_filenames();

  return ruby_cleanup(0);
}
