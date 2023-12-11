#pragma once

#include <stdint.h>

// Used to mark symbols to be exported to the outside of the extension.
// Consider very carefully before tagging a function with this.
#define DDTRACE_EXPORT __attribute__ ((visibility ("default")))

// Used to mark function arguments that are deliberately left unused
#ifdef __GNUC__
  #define DDTRACE_UNUSED  __attribute__((unused))
#else
  #define DDTRACE_UNUSED
#endif

// @ivoanjo: After trying to read through https://stackoverflow.com/questions/3437404/min-and-max-in-c I decided I
// don't like C and I just implemented this as a function.
inline static uint64_t uint64_max_of(uint64_t a, uint64_t b) { return a > b ? a : b; }
inline static uint64_t uint64_min_of(uint64_t a, uint64_t b) { return a > b ? b : a; }

#ifndef __has_c_attribute         // Optional of course.
  #define __has_c_attribute(x) 0  // Compatibility with non-clang compilers.
#endif

// Define GC_SAFE and NOGVL_SAFE macros that serve as annotations that are, respectively, safe to run
// during GC and safe to run without the Ruby Global VM Lock
#if __has_c_attribute(clang::annotate)
  #define GC_SAFE [[clang::annotate("datadog_ruby_gc_safe")]]
  #define NOGVL_SAFE [[clang::annotate("datadog_ruby_nogvl_safe")]]
  #define GVL_GUARD [[clang::annotate("datadog_ruby_gvl_guard")]]
#else
  #define GC_SAFE
  #define NOGVL_SAFE
  #define GVL_GUARD
#endif

