#pragma once

#define MITERUBY_INTERNAL static
#include "../../../ext/datadog_profiling_native_extension/miteruby/can_overflow.c"
#include "../../../ext/datadog_profiling_native_extension/miteruby/allocator.c"
#include "../../../ext/datadog_profiling_native_extension/miteruby/compressed_deltas.c"
#include "../../../ext/datadog_profiling_native_extension/miteruby/raw_events_queue.c"
#include "../../../ext/datadog_profiling_native_extension/miteruby/sample_event.c"
