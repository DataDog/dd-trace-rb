#ifndef DDTRACE_FILTERS_H
#define DDTRACE_FILTERS_H

#include <ruby.h>
#include "datadog_ruby_common.h"

VALUE generate_filter(VALUE self, VALUE to_instrument, VALUE instrumented_files);

#endif // DDTRACE_FILTERS_H