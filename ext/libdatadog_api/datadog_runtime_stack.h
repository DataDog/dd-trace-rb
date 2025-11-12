#pragma once

#include "datadog_ruby_common.h"
#include <datadog/crashtracker.h>

void datadog_runtime_stack_init(VALUE crashtracker_class);

VALUE datadog_runtime_stack_register_callback(void);

VALUE datadog_runtime_stack_is_callback_registered(void);