#pragma once

#include <datadog/profiling.h>
#include <ruby.h>

typedef struct custom_profile custom_profile;

custom_profile *custom_profile_new(void);
void custom_profile_free(custom_profile *profile);
void custom_profile_record_sample(custom_profile *profile, ddog_prof_Sample sample, int64_t timestamp);
VALUE custom_profile_serialize(custom_profile *profile, VALUE start, VALUE finish);
