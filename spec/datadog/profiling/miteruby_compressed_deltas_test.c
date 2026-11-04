#include "../../../ext/datadog_profiling_native_extension/miteruby/pprof/pb_encode.h"

#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "../../../ext/datadog_profiling_native_extension/miteruby/compressed_deltas.c"

static void test_sint32(void) {
  int32_t values[] = {
    INT32_MIN, INT32_MIN + 1, -134217729, -134217728, -1048577, -1048576, -8193, -8192, -65, -64, -1,
    0, 1, 63, 64, 8191, 8192, 1048575, 1048576, 134217727, 134217728, INT32_MAX,
  };
  for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
    uint8_t encoded[5], protobuf[5];
    uint8_t *writer = encoded;
    assert(write_sint32(values[i], &writer, encoded + sizeof(encoded)));
    size_t size = (size_t) (writer - encoded);
    pb_ostream_t stream = pb_ostream_from_buffer(protobuf, sizeof(protobuf));
    assert(pb_encode_svarint(&stream, values[i]));
    assert(stream.bytes_written == size && memcmp(encoded, protobuf, size) == 0);
    const uint8_t *reader = encoded;
    int32_t decoded;
    assert(read_sint32(&decoded, &reader, writer));
    assert(decoded == values[i]);
    assert(reader == writer);
    for (size_t capacity = 0; capacity < size; capacity++) {
      reader = protobuf;
      decoded = 42;
      assert(!read_sint32(&decoded, &reader, protobuf + capacity));
      assert(reader == protobuf + capacity && decoded == 42);
      memset(encoded, 0xa5, sizeof(encoded));
      writer = encoded;
      assert(!write_sint32(values[i], &writer, encoded + capacity));
      assert(writer == encoded + capacity);
      for (size_t j = capacity; j < sizeof(encoded); j++) assert(encoded[j] == 0xa5);
    }
  }
}

static void assert_pair(uint32_t previous, uint32_t current) {
  assert(previous <= UINT20_MAX && current <= UINT20_MAX);
  uint20_t previous_value = {.value = previous};
  uint20_t current_value = {.value = current};
  assert(previous_value.value == previous && current_value.value == current);
  uint8_t encoded[5] = {0, 0, 0, 0xa5, 0xa5};
  uint8_t *writer = encoded;
  assert(miteruby_compressed_deltas_write(previous_value, current_value, &writer, encoded + 3));
  size_t size = (size_t) (writer - encoded);
  assert(size >= 1 && size <= 3 && encoded[3] == 0xa5 && encoded[4] == 0xa5);

  uint8_t protobuf[5];
  pb_ostream_t stream = pb_ostream_from_buffer(protobuf, sizeof(protobuf));
  assert(pb_encode_svarint(&stream, (int32_t) current - (int32_t) previous));
  assert(stream.bytes_written == size && memcmp(encoded, protobuf, size) == 0);
  const uint8_t *reader = encoded;
  uint20_t decoded;
  assert(miteruby_compressed_deltas_read(previous_value, &decoded, &reader, writer));
  assert(decoded.value == current);
  assert(reader == writer);
  assert(size <= miteruby_compressed_deltas_max_size_of(1));
  for (size_t capacity = 0; capacity <= size; capacity++) {
    reader = protobuf;
    decoded = (uint20_t) {.value = 42};
    bool read_success = miteruby_compressed_deltas_read(previous_value, &decoded, &reader, protobuf + capacity);
    assert(read_success == (capacity == size));
    assert(reader == protobuf + capacity);
    assert(decoded.value == (read_success ? current : 42));
    memset(encoded, 0xa5, sizeof(encoded));
    writer = encoded;
    bool success = miteruby_compressed_deltas_write(previous_value, current_value, &writer, encoded + capacity);
    assert(success == (capacity == size));
    assert(writer == encoded + capacity);
    assert(memcmp(encoded, protobuf, capacity) == 0);
    for (size_t i = capacity; i < sizeof(encoded); i++) assert(encoded[i] == 0xa5);
  }
}

static void test_sequences(void) {
  uint8_t encoded[12];
  uint8_t *writer = encoded;
  uint20_t previous = {0};
  for (unsigned int i = 1; i <= 4; i++) {
    uint20_t current = {.value = i};
    assert(miteruby_compressed_deltas_write(previous, current, &writer, encoded + sizeof(encoded)));
    previous = current;
  }
  assert(writer == encoded + 4 && memcmp(encoded, "\x02\x02\x02\x02", 4) == 0);
  const uint8_t *reader = encoded;
  previous = (uint20_t) {0};
  for (unsigned int i = 1; i <= 4; i++) {
    assert(miteruby_compressed_deltas_read(previous, &previous, &reader, writer));
    assert(previous.value == i);
  }
  assert(reader == writer);

  writer = encoded;
  assert(miteruby_compressed_deltas_write((uint20_t) {0}, (uint20_t) {.value = UINT20_MAX}, &writer, encoded + sizeof(encoded)));
  assert(miteruby_compressed_deltas_write((uint20_t) {.value = UINT20_MAX}, (uint20_t) {0}, &writer, encoded + sizeof(encoded)));
  assert(writer == encoded + 6 && memcmp(encoded, "\xfe\xff\x7f\xfd\xff\x7f", 6) == 0);
}

static void test_size_bounds(void) {
  assert(miteruby_compressed_deltas_max_size_of(0) == 0);
  assert(miteruby_compressed_deltas_max_size_of(1) == 3);
  assert(miteruby_compressed_deltas_max_size_of(400) == 1200);
  assert(miteruby_compressed_deltas_max_size_of(UINT16_MAX) == 196605);
}

static void assert_invalid(uint20_t previous, const uint8_t *bytes, size_t size) {
  const uint8_t *reader = bytes;
  uint20_t current = {.value = 42};
  assert(!miteruby_compressed_deltas_read(previous, &current, &reader, bytes + size));
  assert(current.value == 42);
  assert(reader >= bytes && reader <= bytes + size);
}

int main(void) {
  test_sint32();
  assert(UINT20_MAX == (UINT32_C(1) << 20) - 1);
  uint32_t values[] = {0, 1, 63, 64, 127, 128, 8191, 8192, 16383, 16384, UINT16_MAX, 65536, UINT20_MAX - 1, UINT20_MAX};
  for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
    for (size_t j = 0; j < sizeof(values) / sizeof(values[0]); j++) assert_pair(values[i], values[j]);
  }
  test_sequences();
  test_size_bounds();
  assert_invalid((uint20_t) {0}, (uint8_t[]) {0}, 0);
  assert_invalid((uint20_t) {0}, (uint8_t[]) {0x80}, 1);
  assert_invalid((uint20_t) {0}, (uint8_t[]) {0xff, 0xff, 0xff, 0xff, 0x10}, 5);
  assert_invalid((uint20_t) {0}, (uint8_t[]) {0x80, 0x80, 0x80, 0x80, 0x80, 0}, 6);
  assert_invalid((uint20_t) {0}, (uint8_t[]) {0xff, 0xff, 0x7f}, 3);
  assert_invalid((uint20_t) {0}, (uint8_t[]) {1}, 1);
  assert_invalid((uint20_t) {.value = UINT20_MAX}, (uint8_t[]) {2}, 1);
  puts("Miteruby compressed deltas tests passed");
  return 0;
}
