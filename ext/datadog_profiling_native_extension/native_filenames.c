#ifndef _GNU_SOURCE
  #define _GNU_SOURCE 1 // Needed for dlfcn.h/dladdr
#endif
#include <dlfcn.h>

#include "native_filenames.h"
#include "miteruby/allocator.h"
#include "helpers.h"

// Enough to hold ~131k buckets => ~117k entries given our 16-byte key/value pairs
#define NATIVE_FILENAMES_MAX_BYTES KiB_AS_BYTES(2400)

static void *native_filenames_alloc(size_t size) {
  if (size > NATIVE_FILENAMES_MAX_BYTES) return NULL;
  return miteruby_allocator_alloc(size, "native_filenames_cache");
}

#define NAME native_filenames_cache
#define KEY_TY uintptr_t
#define VAL_TY const char *
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#define MALLOC_FN native_filenames_alloc
#define FREE_FN miteruby_allocator_free_sized
#define IMPLEMENTATION_MODE
#include "miteruby/hashtable/verstable.h"

// NULL if we weren't able to get the native filename for the Ruby VM.
// On a static Ruby without libruby.so, `lookup_filename` returns `ruby_native_filename` but
// `static_ruby_actual_filename` (below) is what we want to show instead.
static const char *ruby_native_filename = NULL;
// Qnil unless we're running on a static Ruby
static VALUE static_ruby_actual_filename = Qnil;

// `cache` is used to cache native filename lookup results (Map[native_function_pointer, char *filename])
//
// Caching this information is safe because there's no API in Ruby to "unrequire" a native extension. Thus, if we see a
// frame on the **Ruby** stack with a given `function`, then that `function` was registered with the Ruby VM and
// belongs to a Ruby extension, so a lot of other bad things would happen if it was dlclosed.
//
// Returns "" if not found. Never returns NULL.
static const char *lookup_filename(native_filenames_cache *cache, native_function_pointer function) {
  native_filenames_cache_itr entry = native_filenames_cache_get(cache, (uintptr_t) function);
  if (!native_filenames_cache_is_end(entry)) return entry.data->val;

  Dl_info info;
  const char *filename = dladdr((const void *) function, &info) != 0 ? info.dli_fname : NULL;

  // We explicitly use an empty string here so as to cache lookups that somehow "failed". Otherwise we would keep trying them every time.
  if (filename == NULL) filename = "";

  entry = native_filenames_cache_insert(cache, (uintptr_t) function, filename);
  if (native_filenames_cache_is_end(entry)) {
    native_filenames_cache_clear(cache);
    // If insertion fails, the resolved path is still usable; only subsequent lookups lose the benefit of caching.
    native_filenames_cache_insert(cache, (uintptr_t) function, filename);
  }
  return filename;
}

void native_filenames_init(VALUE profiling_module) {
  // To be able to detect when a frame is coming from Ruby, we record here its filename as returned by dladdr.
  // We expect this same pointer to be returned by dladdr for all frames coming from Ruby.
  //
  // Small note: Creating/deleting the cache is a bit awkward here, but it seems like a bigger footgun to allow
  // `lookup_filename` to run without a cache, since we never expect that to happen during sampling. So it seems
  // like a reasonable trade-off to force callers to always figure that out.
  native_filenames_cache cache;
  native_filenames_cache_init(&cache);
  const char *filename = lookup_filename(&cache, (native_function_pointer) rb_ary_new);
  native_filenames_cache_cleanup(&cache);
  if (filename[0] == '\0') return;

  ruby_native_filename = filename;
  // On a static Ruby without libruby.so the `ruby_native_filename` returned from `dladdr` is in practice `argv[0]`
  // (e.g. can be rspec, rake, etc), so here we find the actual Ruby binary to use instead
  static_ruby_actual_filename = rb_const_get(profiling_module, rb_intern("STATIC_RUBY_PATH"));
  if (!NIL_P(static_ruby_actual_filename)) {
    StringValueCStr(static_ruby_actual_filename);
    // Makes this object immortal + pinned in-place (no moving)
    rb_gc_register_mark_object(static_ruby_actual_filename);
  }
}

VALUE native_filenames_ruby_filename(void) {
  if (!NIL_P(static_ruby_actual_filename)) return static_ruby_actual_filename;
  return ruby_native_filename != NULL ? rb_utf8_str_new_cstr(ruby_native_filename) : Qnil;
}

native_filename native_filenames_lookup(native_filenames_cache *cache, native_function_pointer function) {
  const char *filename = lookup_filename(cache, function);
  // dladdr is expected to always return the same pointer to the ruby_native_filename, so that's why we're
  // comparing only pointer values and not the string contents.
  bool is_ruby = filename == ruby_native_filename;
  // On a static Ruby without libruby.so, we show `static_ruby_actual_filename` instead of `ruby_native_filename`
  if (is_ruby && !NIL_P(static_ruby_actual_filename)) filename = RSTRING_PTR(static_ruby_actual_filename);
  return (native_filename) {.path = filename, .is_ruby = is_ruby};
}

VALUE native_filenames_testing_resolve(VALUE self, VALUE static_ruby_filename) {
  (void) self;
  if (!NIL_P(static_ruby_filename)) StringValueCStr(static_ruby_filename);
  VALUE previous = static_ruby_actual_filename;
  static_ruby_actual_filename = static_ruby_filename;
  native_filenames_cache cache;
  native_filenames_cache_init(&cache);
  native_filename filename = native_filenames_lookup(&cache, (native_function_pointer) rb_ary_new); // Symbol inside Ruby VM to trigger comparison logic
  native_filenames_cache_cleanup(&cache);
  static_ruby_actual_filename = previous;
  VALUE result = rb_utf8_str_new_cstr(filename.path);
  RB_GC_GUARD(static_ruby_filename);
  return result;
}
