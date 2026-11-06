#pragma once

#include <stdint.h>

typedef struct {
  int64_t cpu_time_ns;
  uint32_t cpu_or_wall_samples;
  int64_t wall_time_ns;
  uint32_t alloc_samples;
  uint32_t alloc_samples_unscaled;
  int64_t timeline_wall_time_ns;
} miteruby_sample_values;
