#include "custom_profile.h"
#include "../datadog_ruby_common.h"
#include "pprof/pb_encode.h"
#include "pprof/pprof_fragments.pb.h"

#include <stdlib.h>
#include <string.h>

// The bundled single-file zstd build has no separate header.
size_t ZSTD_compressBound(size_t src_size);
size_t ZSTD_compress(void *dst, size_t capacity, const void *src, size_t size, int level);
unsigned ZSTD_isError(size_t result);
const char *ZSTD_getErrorName(size_t result);

enum { END_TIMESTAMP_NS = 3 };

typedef struct allocation {
  struct allocation *next;
  void *pointer;
} allocation;

typedef struct {
  void **items;
  size_t count;
  const pb_msgdesc_t *fields;
} messages;

typedef struct {
  uint64_t *items;
  size_t count;
} integers;

typedef struct {
  miteruby_pprof_fragment_sample_t message;
  integers locations;
  integers values;
  messages labels;
  int64_t timestamp;
} sample;

struct custom_profile {
  allocation *allocations;
  messages strings;
  messages functions;
  messages locations;
  messages samples;
};

static void *allocate(custom_profile *profile, size_t count, size_t size) {
  allocation *entry = malloc(sizeof(allocation));
  if (entry == NULL) rb_memerror();
  entry->pointer = calloc(count ? count : 1, size);
  if (entry->pointer == NULL) {
    free(entry);
    rb_memerror();
  }
  entry->next = profile->allocations;
  profile->allocations = entry;
  return entry->pointer;
}

static void append(messages *array, void *item) {
  if (array->count >= SIZE_MAX / sizeof(void *) - 1) rb_memerror();
  void **items = realloc(array->items, (array->count + 1) * sizeof(void *));
  if (items == NULL) rb_memerror();
  array->items = items;
  array->items[array->count++] = item;
}

custom_profile *custom_profile_new(void) {
  custom_profile *profile = calloc(1, sizeof(custom_profile));
  if (profile == NULL) rb_memerror();
  profile->functions.fields = MITERUBY_PPROF_FRAGMENT_FUNCTION_FIELDS;
  profile->locations.fields = MITERUBY_PPROF_FRAGMENT_LOCATION_FIELDS;
  profile->samples.fields = MITERUBY_PPROF_FRAGMENT_SAMPLE_FIELDS;
  return profile;
}

void custom_profile_free(custom_profile *profile) {
  if (profile == NULL) return;
  for (size_t i = 0; i < profile->samples.count; i++) {
    sample *item = profile->samples.items[i];
    free(item->labels.items);
  }
  free(profile->strings.items);
  free(profile->functions.items);
  free(profile->locations.items);
  free(profile->samples.items);
  allocation *entry = profile->allocations;
  while (entry != NULL) {
    allocation *next = entry->next;
    free(entry->pointer);
    free(entry);
    entry = next;
  }
  free(profile);
}

static int64_t intern_string(custom_profile *profile, ddog_CharSlice string) {
  for (size_t i = 0; i < profile->strings.count; i++) {
    ddog_CharSlice *existing = profile->strings.items[i];
    if (existing->len == string.len && (string.len == 0 || memcmp(existing->ptr, string.ptr, string.len) == 0)) return i;
  }
  ddog_CharSlice *copy = allocate(profile, 1, sizeof(ddog_CharSlice));
  char *bytes = allocate(profile, string.len, 1);
  if (string.len > 0) memcpy(bytes, string.ptr, string.len);
  *copy = (ddog_CharSlice) {.ptr = bytes, .len = string.len};
  append(&profile->strings, copy);
  return profile->strings.count - 1;
}

static void initialize_strings(custom_profile *profile) {
  if (profile->strings.count != 0) return;
  // Match libdatadog's prefilled table, including unused strings, to preserve string IDs in decoded comparisons.
  intern_string(profile, DDOG_CHARSLICE_C(""));
  intern_string(profile, DDOG_CHARSLICE_C("local root span id"));
  intern_string(profile, DDOG_CHARSLICE_C("trace endpoint"));
  intern_string(profile, DDOG_CHARSLICE_C("end_timestamp_ns"));
}

static bool encode_messages(pb_ostream_t *stream, const pb_field_t *field, void *const *arg) {
  const messages *array = *arg;
  for (size_t i = 0; i < array->count; i++) {
    if (!pb_encode_tag_for_field(stream, field) || !pb_encode_submessage(stream, array->fields, array->items[i])) return false;
  }
  return true;
}

static bool encode_integers(pb_ostream_t *stream, const pb_field_t *field, void *const *arg) {
  const integers *array = *arg;
  pb_ostream_t size = PB_OSTREAM_SIZING;
  for (size_t i = 0; i < array->count; i++) {
    if (!pb_encode_varint(&size, array->items[i])) return false;
  }
  if (!pb_encode_tag(stream, PB_WT_STRING, field->tag) || !pb_encode_varint(stream, size.bytes_written)) return false;
  for (size_t i = 0; i < array->count; i++) {
    if (!pb_encode_varint(stream, array->items[i])) return false;
  }
  return true;
}

static bool encode_strings(pb_ostream_t *stream, const pb_field_t *field, void *const *arg) {
  const messages *strings = *arg;
  for (size_t i = 0; i < strings->count; i++) {
    const ddog_CharSlice *string = strings->items[i];
    if (!pb_encode_tag_for_field(stream, field) || !pb_encode_string(stream, (const pb_byte_t *) string->ptr, string->len)) return false;
  }
  return true;
}

static uint64_t intern_function(custom_profile *profile, ddog_prof_Function function) {
  miteruby_pprof_fragment_function_function_t value = {
    .name = intern_string(profile, function.name), .filename = intern_string(profile, function.filename),
  };
  for (size_t i = 0; i < profile->functions.count; i++) {
    miteruby_pprof_fragment_function_t *existing = profile->functions.items[i];
    if (existing->function.name == value.name && existing->function.filename == value.filename) return existing->function.id;
  }
  miteruby_pprof_fragment_function_t *copy = allocate(profile, 1, sizeof(*copy));
  *copy = (miteruby_pprof_fragment_function_t) {.has_function = true, .function = value};
  copy->function.id = profile->functions.count + 1;
  append(&profile->functions, copy);
  return copy->function.id;
}

static uint64_t intern_location(custom_profile *profile, ddog_prof_Location location) {
  uint64_t function_id = intern_function(profile, location.function);
  for (size_t i = 0; i < profile->locations.count; i++) {
    miteruby_pprof_fragment_location_t *existing = profile->locations.items[i];
    if (existing->location.line.function_id == function_id && existing->location.line.line == location.line) return existing->location.id;
  }
  miteruby_pprof_fragment_location_t *copy = allocate(profile, 1, sizeof(*copy));
  *copy = (miteruby_pprof_fragment_location_t) {
    .has_location = true,
    .location = {
      .id = profile->locations.count + 1, .has_line = true,
      .line = {.function_id = function_id, .line = location.line},
    },
  };
  append(&profile->locations, copy);
  return copy->location.id;
}

static bool same_sample(sample *a, sample *b) {
  if (a->timestamp || b->timestamp || a->locations.count != b->locations.count || a->labels.count != b->labels.count) return false;
  for (size_t i = 0; i < a->locations.count; i++) {
    if (a->locations.items[i] != b->locations.items[i]) return false;
  }
  for (size_t i = 0; i < a->labels.count; i++) {
    miteruby_pprof_fragment_sample_sample_label_t *left = a->labels.items[i];
    miteruby_pprof_fragment_sample_sample_label_t *right = b->labels.items[i];
    if (left->key != right->key || left->str != right->str || left->num != right->num) return false;
  }
  return true;
}

void custom_profile_record_sample(custom_profile *profile, ddog_prof_Sample input, int64_t timestamp) {
  initialize_strings(profile);
  sample *item = allocate(profile, 1, sizeof(*item));
  item->labels.fields = MITERUBY_PPROF_FRAGMENT_SAMPLE_SAMPLE_LABEL_FIELDS;
  item->timestamp = timestamp;
  item->locations = (integers) {.count = input.locations.len, .items = allocate(profile, input.locations.len, sizeof(uint64_t))};
  item->values = (integers) {.count = input.values.len, .items = allocate(profile, input.values.len, sizeof(uint64_t))};
  item->message = (miteruby_pprof_fragment_sample_t) {
    .has_sample = true,
    .sample = {
      .location_id = {.funcs.encode = encode_integers, .arg = &item->locations},
      .value = {.funcs.encode = encode_integers, .arg = &item->values},
      .label = {.funcs.encode = encode_messages, .arg = &item->labels},
    },
  };
  // Attach before any further allocations so cleanup also owns partially built samples.
  append(&profile->samples, item);
  for (size_t i = 0; i < input.labels.len; i++) {
    ddog_prof_Label label = input.labels.ptr[i];
    miteruby_pprof_fragment_sample_sample_label_t *copy = allocate(profile, 1, sizeof(*copy));
    copy->key = intern_string(profile, label.key);
    if (label.str.len) copy->str = intern_string(profile, label.str);
    else copy->num = label.num;
    append(&item->labels, copy);
  }
  for (size_t i = 0; i < input.locations.len; i++) item->locations.items[i] = intern_location(profile, input.locations.ptr[i]);
  for (size_t i = 0; i < input.values.len; i++) item->values.items[i] = (uint64_t) input.values.ptr[i];
  if (timestamp != 0) return;

  for (size_t i = 0; i + 1 < profile->samples.count; i++) {
    sample *existing = profile->samples.items[i];
    if (!same_sample(existing, item)) continue;
    for (size_t j = 0; j < item->values.count; j++) {
      int64_t left = (int64_t) existing->values.items[j], right = (int64_t) item->values.items[j];
      existing->values.items[j] = (right > 0 && left > INT64_MAX - right) ? INT64_MAX :
        (right < 0 && left < INT64_MIN - right) ? INT64_MIN : left + right;
    }
    free(item->labels.items);
    profile->samples.count--;
    return;
  }
}

static void add_timestamps(custom_profile *profile) {
  for (size_t i = 0; i < profile->samples.count; i++) {
    sample *item = profile->samples.items[i];
    if (item->timestamp) {
      miteruby_pprof_fragment_sample_sample_label_t *extra = allocate(profile, 1, sizeof(*extra));
      *extra = (miteruby_pprof_fragment_sample_sample_label_t) {.key = END_TIMESTAMP_NS, .num = item->timestamp};
      append(&item->labels, extra);
    }
  }
}

static bool encode_fragments(pb_ostream_t *stream, const messages *array) {
  for (size_t i = 0; i < array->count; i++) {
    if (!pb_encode(stream, array->fields, array->items[i])) return false;
  }
  return true;
}

static bool encode_profile(
  pb_ostream_t *stream, custom_profile *profile, const messages *sample_types,
  const miteruby_pprof_fragment_profile_t *metadata
) {
  miteruby_pprof_fragment_string_table_t strings = {
    .string_table = {.funcs.encode = encode_strings, .arg = &profile->strings},
  };
  return encode_fragments(stream, sample_types) &&
    encode_fragments(stream, &profile->samples) &&
    encode_fragments(stream, &profile->locations) &&
    encode_fragments(stream, &profile->functions) &&
    pb_encode(stream, MITERUBY_PPROF_FRAGMENT_STRING_TABLE_FIELDS, &strings) &&
    pb_encode(stream, MITERUBY_PPROF_FRAGMENT_PROFILE_FIELDS, metadata);
}

VALUE custom_profile_serialize(custom_profile *profile, VALUE start, VALUE finish) {
  initialize_strings(profile);
  add_timestamps(profile);
  const char *names[] = {"cpu-time", "cpu-samples", "wall-time", "alloc-samples", "alloc-samples-unscaled", "timeline"};
  const char *units[] = {"nanoseconds", "count", "nanoseconds", "count", "count", "nanoseconds"};
  miteruby_pprof_fragment_sample_type_t types[6];
  void *type_pointers[6];
  for (size_t i = 0; i < 6; i++) {
    types[i] = (miteruby_pprof_fragment_sample_type_t) {
      .has_sample_type = true,
      .sample_type = {
        .type = intern_string(profile, (ddog_CharSlice) {.ptr = names[i], .len = strlen(names[i])}),
        .unit = intern_string(profile, (ddog_CharSlice) {.ptr = units[i], .len = strlen(units[i])}),
      },
    };
    type_pointers[i] = &types[i];
  }
  messages sample_types = {.items = type_pointers, .count = 6, .fields = MITERUBY_PPROF_FRAGMENT_SAMPLE_TYPE_FIELDS};
  struct timespec start_time = rb_time_timespec(start), finish_time = rb_time_timespec(finish);
  int64_t time_ns = start_time.tv_sec * INT64_C(1000000000) + start_time.tv_nsec;
  int64_t duration_ns = (finish_time.tv_sec - start_time.tv_sec) * INT64_C(1000000000) + finish_time.tv_nsec - start_time.tv_nsec;
  miteruby_pprof_fragment_profile_t metadata = {
    .time_nanos = time_ns, .duration_nanos = duration_ns > 0 ? duration_ns : 0,
  };
  pb_ostream_t sizing = PB_OSTREAM_SIZING;
  if (!encode_profile(&sizing, profile, &sample_types, &metadata)) rb_raise(rb_eRuntimeError, "Failed to size custom pprof");
  size_t size = sizing.bytes_written;
  void *bytes = allocate(profile, size, 1);
  pb_ostream_t stream = pb_ostream_from_buffer(bytes, size);
  if (!encode_profile(&stream, profile, &sample_types, &metadata)) rb_raise(rb_eRuntimeError, "Failed to encode custom pprof: %s", PB_GET_ERROR(&stream));
  size_t capacity = ZSTD_compressBound(size);
  if (ZSTD_isError(capacity)) rb_raise(rb_eRuntimeError, "Failed to size zstd buffer: %s", ZSTD_getErrorName(capacity));
  void *compressed = allocate(profile, capacity, 1);
  size_t compressed_size = ZSTD_compress(compressed, capacity, bytes, stream.bytes_written, 1);
  if (ZSTD_isError(compressed_size)) rb_raise(rb_eRuntimeError, "Failed to compress custom pprof: %s", ZSTD_getErrorName(compressed_size));
  VALUE bytes_string = rb_str_new(compressed, compressed_size);
  return rb_funcall(rb_path2class("Datadog::Profiling::EncodedProfile"), rb_intern("from_custom"), 3, start, finish, bytes_string);
}
