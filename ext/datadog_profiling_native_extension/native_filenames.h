#pragma once

#include <ruby.h>
#include <stdbool.h>
#include <stdint.h>

#define NAME native_filenames_cache
#define KEY_TY uintptr_t
#define VAL_TY const char *
#define HEADER_MODE
#include "miteruby/hashtable/verstable.h"

typedef void (*native_function_pointer)(void);

typedef struct {
  const char *path;
  bool is_ruby;
} native_filename;

void native_filenames_init(VALUE profiling_module);
VALUE native_filenames_ruby_filename(void);

// Requires the GVL and exclusive cache access. Paths are borrowed; missing filenames are "", never NULL.
native_filename native_filenames_lookup(native_filenames_cache *cache, native_function_pointer function);

VALUE native_filenames_testing_resolve(VALUE self, VALUE static_ruby_filename);
