#define _GNU_SOURCE 1 // For can_overflow.c, needs to come before other system headers
#include "miteruby_unity.h"

// Poor person's LTO. Building miteruby as one translation unit lets the compiler
// inline calls across source files. In our measurements, this sped up serialization,
// shortened clean builds, and made the profiler shared library smaller.
//
// Include each new miteruby .c file here so it gets built.
// And it's easy to undo if we ever change our minds?
#include "miteruby/can_overflow.c"
#include "miteruby/allocator.c"
#include "miteruby/compressed_deltas.c"
#include "miteruby/raw_events_queue.c"
#include "miteruby/raw_events_queue_marking.c"
#include "miteruby/sample_event.c"
#include "miteruby/stack_dedup.c"
#include "miteruby/consumer.c"
#include "miteruby/pprof/pb_common.c"
#include "miteruby/pprof/pb_encode.c"
#include "miteruby/pprof/pprof_fragments.pb.c"
#include "miteruby/pprof/zstd.c" // Needs to come before serializer.c
#include "miteruby/serializer.c"
