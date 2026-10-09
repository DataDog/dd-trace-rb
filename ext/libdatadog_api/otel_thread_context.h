#pragma once

#include <ruby.h>
#include <stdbool.h>

void otel_thread_context_init(VALUE tracing_module);
bool otel_thread_context_was_enabled(void);
