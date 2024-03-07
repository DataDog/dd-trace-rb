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
inline static long long_max_of(long a, long b) { return a > b ? a : b; }
inline static long long_min_of(long a, long b) { return a > b ? b : a; }
inline static double double_max_of(double a, double b) { return a > b ? a : b; }
inline static double double_min_of(double a, double b) { return a > b ? b : a; }
