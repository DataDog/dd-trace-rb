#pragma once

#include "datadog_ruby_common.h"

void crashtracker_init(VALUE core_module);
void ruby_crash_reporting_init(VALUE crashtracking_module);
