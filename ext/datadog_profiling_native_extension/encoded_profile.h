#pragma once

#include <ruby.h>
#include <datadog/profiling.h>

VALUE from_ddog_prof_EncodedProfile(ddog_prof_EncodedProfile profile);
