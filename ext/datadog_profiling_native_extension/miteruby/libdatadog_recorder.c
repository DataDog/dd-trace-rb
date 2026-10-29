#include "libdatadog_recorder.h"
#include "../datadog_ruby_common.h"
#include "../encoded_profile.h"
#include "../helpers.h"
#include "../ruby_helpers.h"
#include "../time_helpers.h"

#include <ruby/thread.h>

static const ddog_prof_SampleType sample_types[] = {
  DDOG_PROF_SAMPLE_TYPE_CPU_TIME,
  DDOG_PROF_SAMPLE_TYPE_CPU_SAMPLES,
  DDOG_PROF_SAMPLE_TYPE_WALL_TIME,
  DDOG_PROF_SAMPLE_TYPE_ALLOC_SAMPLES,
  DDOG_PROF_SAMPLE_TYPE_ALLOC_SAMPLES_UNSCALED,
  DDOG_PROF_SAMPLE_TYPE_TIMELINE,
};

typedef struct {
  ddog_prof_Profile profile;
  ddog_Timespec start_timestamp;
  // Only accessed with the GVL. The serializer exclusively owns profile while this is true.
  bool serializing;
  uint64_t recorded_samples;
  uint64_t serialization_successes;
  uint64_t serialization_failures;
  long serialization_time_ns_min;
  long serialization_time_ns_max;
  uint64_t serialization_time_ns_total;
} recorder_state;

typedef struct {
  recorder_state *state;
  ddog_Timespec finish_timestamp;
  ddog_prof_Profile_SerializeResult result;
  long duration_ns;
  bool ran;
  bool owns_result;
} serialize_args;

static void recorder_free(void *data) {
  recorder_state *state = data;
  ddog_prof_Profile_drop(&state->profile);
  ruby_xfree(state);
}

static size_t recorder_size(const void *data) {
  return data ? sizeof(recorder_state) : 0;
}

static const rb_data_type_t recorder_type = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::LibdatadogRecorder",
  .function = {.dfree = recorder_free, .dsize = recorder_size},
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static recorder_state *get_state(VALUE recorder) {
  recorder_state *state;
  TypedData_Get_Struct(recorder, recorder_state, &recorder_type, state);
  return state;
}

static recorder_state *available_state(VALUE recorder) {
  recorder_state *state = get_state(recorder);
  if (state->serializing) rb_raise(rb_eRuntimeError, "Miteruby recorder is being serialized");
  return state;
}

VALUE miteruby_libdatadog_recorder_enforce_available(VALUE recorder) {
  available_state(recorder);
  return recorder;
}

static ddog_Timespec epoch_now(void) {
  long now_ns = system_epoch_time_now_ns();
  return (ddog_Timespec) {.seconds = now_ns / SECONDS_AS_NS(1), .nanoseconds = now_ns % SECONDS_AS_NS(1)};
}

static VALUE ruby_time(ddog_Timespec timestamp) {
  struct timespec time = {.tv_sec = timestamp.seconds, .tv_nsec = timestamp.nanoseconds};
  return rb_time_timespec_new(&time, INT_MAX - 1);
}

static VALUE recorder_new(VALUE klass) {
  recorder_state *state;
  VALUE recorder = TypedData_Make_Struct(klass, recorder_state, &recorder_type, state);
  state->start_timestamp = epoch_now();
  state->serialization_time_ns_min = INT64_MAX;
  ddog_prof_Profile_NewResult result = ddog_prof_Profile_new(
    (ddog_prof_Slice_SampleType) {.ptr = sample_types, .len = sizeof(sample_types) / sizeof(sample_types[0])}, NULL
  );
  if (result.tag == DDOG_PROF_PROFILE_NEW_RESULT_ERR)
    raise_error(rb_eRuntimeError, "Failed to initialize miteruby profile: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  state->profile = result.ok;
  return recorder;
}

void miteruby_libdatadog_recorder_record_sample(
  VALUE recorder, ddog_prof_Slice_Location locations, miteruby_sample_values values,
  ddog_prof_Slice_Label labels, int64_t end_timestamp_ns
) {
  recorder_state *state = available_state(recorder);
  int64_t metrics[] = {
    values.cpu_time_ns, values.cpu_or_wall_samples, values.wall_time_ns,
    values.alloc_samples, values.alloc_samples_unscaled, values.timeline_wall_time_ns,
  };
  ddog_prof_Profile_Result result = ddog_prof_Profile_add(
    &state->profile,
    (ddog_prof_Sample) {
      .locations = locations,
      .values = {.ptr = metrics, .len = sizeof(metrics) / sizeof(metrics[0])},
      .labels = labels,
    },
    end_timestamp_ns
  );
  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR)
    raise_error(rb_eArgError, "Failed to record sample: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  state->recorded_samples++;
}

static void *serialize_without_gvl(void *data) {
  serialize_args *args = data;
  long start_ns = monotonic_wall_time_now_ns();
  args->result = ddog_prof_Profile_serialize(&args->state->profile, &args->state->start_timestamp, &args->finish_timestamp);
  args->duration_ns = long_max_of(0, monotonic_wall_time_now_ns() - start_ns);
  args->ran = true;
  args->owns_result = true;
  return NULL;
}

static VALUE serialize_owned(VALUE data) {
  serialize_args *args = (serialize_args *) data;
  rb_thread_call_without_gvl(serialize_without_gvl, args, NULL, NULL);

  if (args->result.tag == DDOG_PROF_PROFILE_SERIALIZE_RESULT_ERR) {
    return rb_ary_new_from_args(2, ID2SYM(rb_intern("error")), ruby_string_from_error(&args->result.err));
  }

  VALUE encoded = from_ddog_prof_EncodedProfile(args->result.ok);
  args->owns_result = false;
  VALUE stats = rb_hash_new();
  rb_hash_aset(stats, ID2SYM(rb_intern("recorded_samples")), ULL2NUM(args->state->recorded_samples));
  rb_hash_aset(stats, ID2SYM(rb_intern("serialization_time_ns")), LONG2NUM(args->duration_ns));
  return rb_ary_new_from_args(2, ID2SYM(rb_intern("ok")), rb_ary_new_from_args(
    4, ruby_time(args->state->start_timestamp), ruby_time(args->finish_timestamp), encoded, stats
  ));
}

static VALUE serialize_cleanup(VALUE data) {
  serialize_args *args = (serialize_args *) data;
  recorder_state *state = args->state;
  if (args->ran) {
    bool success = args->result.tag == DDOG_PROF_PROFILE_SERIALIZE_RESULT_OK;
    if (success) state->serialization_successes++;
    else state->serialization_failures++;
    state->serialization_time_ns_min = long_min_of(state->serialization_time_ns_min, args->duration_ns);
    state->serialization_time_ns_max = long_max_of(state->serialization_time_ns_max, args->duration_ns);
    state->serialization_time_ns_total += args->duration_ns;
    // libdatadog resets the profile during serialization, including when Ruby interrupts the return to the GVL.
    state->start_timestamp = args->finish_timestamp;
    state->recorded_samples = 0;
    if (args->owns_result) {
      if (success) ddog_prof_EncodedProfile_drop(&args->result.ok);
      else ddog_Error_drop(&args->result.err);
    }
  }
  state->serializing = false;
  return Qnil;
}

static VALUE native_serialize(DDTRACE_UNUSED VALUE klass, VALUE recorder) {
  serialize_args args = {.state = available_state(recorder), .finish_timestamp = epoch_now()};
  args.state->serializing = true;
  VALUE result = rb_ensure(serialize_owned, (VALUE) &args, serialize_cleanup, (VALUE) &args);
  RB_GC_GUARD(recorder);
  return result;
}

static VALUE native_reset_after_fork(DDTRACE_UNUSED VALUE klass, VALUE recorder) {
  recorder_state *state = available_state(recorder);
  ddog_prof_Profile_Result result = ddog_prof_Profile_reset(&state->profile);
  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR)
    raise_error(rb_eRuntimeError, "Failed to reset profile: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  state->start_timestamp = epoch_now();
  state->recorded_samples = 0;
  return Qtrue;
}

static VALUE native_stats(DDTRACE_UNUSED VALUE klass, VALUE recorder) {
  recorder_state *state = get_state(recorder);
  uint64_t count = state->serialization_successes + state->serialization_failures;
  VALUE stats = rb_hash_new();
  VALUE entries[] = {
    ID2SYM(rb_intern("serialization_successes")), ULL2NUM(state->serialization_successes),
    ID2SYM(rb_intern("serialization_failures")), ULL2NUM(state->serialization_failures),
    ID2SYM(rb_intern("serialization_time_ns_min")), count ? LONG2NUM(state->serialization_time_ns_min) : Qnil,
    ID2SYM(rb_intern("serialization_time_ns_max")), count ? LONG2NUM(state->serialization_time_ns_max) : Qnil,
    ID2SYM(rb_intern("serialization_time_ns_total")), count ? ULL2NUM(state->serialization_time_ns_total) : Qnil,
    ID2SYM(rb_intern("serialization_time_ns_avg")), RUBY_AVG_OR_NIL(state->serialization_time_ns_total, count),
  };
  for (size_t i = 0; i < VALUE_COUNT(entries); i += 2) rb_hash_aset(stats, entries[i], entries[i + 1]);
  return stats;
}

static VALUE testing_record_sample(DDTRACE_UNUSED VALUE klass, VALUE recorder, VALUE metrics, VALUE timestamp) {
  Check_Type(metrics, T_ARRAY);
  if (RARRAY_LEN(metrics) != 6) rb_raise(rb_eArgError, "Expected six sample values");
  miteruby_sample_values values = {
    .cpu_time_ns = NUM2LL(rb_ary_entry(metrics, 0)),
    .cpu_or_wall_samples = NUM2UINT(rb_ary_entry(metrics, 1)),
    .wall_time_ns = NUM2LL(rb_ary_entry(metrics, 2)),
    .alloc_samples = NUM2UINT(rb_ary_entry(metrics, 3)),
    .alloc_samples_unscaled = NUM2UINT(rb_ary_entry(metrics, 4)),
    .timeline_wall_time_ns = NUM2LL(rb_ary_entry(metrics, 5)),
  };
  miteruby_libdatadog_recorder_record_sample(
    recorder, (ddog_prof_Slice_Location) {0}, values, (ddog_prof_Slice_Label) {0}, NUM2LL(timestamp)
  );
  return Qnil;
}

static VALUE testing_with_serialization_ownership(DDTRACE_UNUSED VALUE klass, VALUE recorder) {
  serialize_args args = {.state = available_state(recorder)};
  args.state->serializing = true;
  VALUE result = rb_ensure(rb_yield, Qnil, serialize_cleanup, (VALUE) &args);
  RB_GC_GUARD(recorder);
  return result;
}

void miteruby_libdatadog_recorder_init(VALUE profiling_module) {
  VALUE miteruby = rb_define_module_under(profiling_module, "Miteruby");
  VALUE klass = rb_define_class_under(miteruby, "LibdatadogRecorder", rb_cObject);
  rb_define_alloc_func(klass, recorder_new);
  rb_define_singleton_method(klass, "_native_serialize", native_serialize, 1);
  rb_define_singleton_method(klass, "_native_reset_after_fork", native_reset_after_fork, 1);
  rb_define_singleton_method(klass, "_native_stats", native_stats, 1);
  VALUE testing = rb_define_module_under(klass, "Testing");
  rb_define_singleton_method(testing, "_native_record_sample", testing_record_sample, 3);
  rb_define_singleton_method(testing, "_native_with_serialization_ownership", testing_with_serialization_ownership, 1);
}
