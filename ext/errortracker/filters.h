#ifndef DDTRACE_FILTERS_H
#define DDTRACE_FILTERS_H

#include <ruby.h>
#include "datadog_ruby_common.h"

VALUE generate_filter(VALUE self, VALUE to_instrument);
VALUE _proc_filter_all(VALUE self, VALUE tp);
VALUE _proc_filter_user(VALUE self, VALUE tp);
VALUE _proc_filter_third_party(VALUE self, VALUE tp);
VALUE _get_gem_name(VALUE file_name);

#endif // DDTRACE_FILTERS_H