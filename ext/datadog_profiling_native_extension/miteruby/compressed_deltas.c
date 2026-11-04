#include "compressed_deltas.h"

// Protobuf varints emit seven low bits per byte; the high bit indicates another byte follows.
__attribute__((warn_unused_result))
static bool write_varint(uint32_t value, uint8_t **cursor, const uint8_t *end) {
  do {
    if (*cursor >= end) return false;
    uint8_t byte = (uint8_t) (value & 0x7f);
    value >>= 7;
    *(*cursor)++ = (uint8_t) (byte | (value ? 0x80 : 0));
  } while (value);
  return true;
}

// Reads the same protobuf payload format, bounded to uint32_t (the unsigned payload of sint32).
__attribute__((warn_unused_result))
static bool read_varint(uint32_t *decoded_value, const uint8_t **cursor, const uint8_t *end) {
  uint32_t value = 0;
  for (unsigned int shift = 0; shift < 35 && *cursor < end; shift += 7) {
    uint8_t byte = *(*cursor)++;
    if (shift == 28 && byte > 0x0f) return false;
    value |= (uint32_t) (byte & 0x7f) << shift;
    if (!(byte & 0x80)) {
      *decoded_value = value;
      return true;
    }
  }
  return false;
}

// Protobuf sint32 payloads use ZigZag followed by a varint; unsigned arithmetic also handles INT32_MIN.
__attribute__((warn_unused_result))
static bool write_sint32(int32_t value, uint8_t **cursor, const uint8_t *end) {
  uint32_t zigzag = ((uint32_t) value << 1) ^ (value < 0 ? UINT32_MAX : 0);
  return write_varint(zigzag, cursor, end);
}

__attribute__((warn_unused_result))
static bool read_sint32(int32_t *value, const uint8_t **cursor, const uint8_t *end) {
  uint32_t zigzag;
  if (!read_varint(&zigzag, cursor, end)) return false;
  *value = (zigzag & 1) ? -(int32_t) (zigzag / 2) - 1 : (int32_t) (zigzag / 2);
  return true;
}

bool miteruby_compressed_deltas_write(uint20_t previous_value, uint20_t current_value, uint8_t **cursor, const uint8_t *end) {
  int32_t delta = (int32_t) current_value.value - (int32_t) previous_value.value;
  return write_sint32(delta, cursor, end);
}

bool miteruby_compressed_deltas_read(uint20_t previous_value, uint20_t *current_value, const uint8_t **cursor, const uint8_t *end) {
  int32_t delta;
  if (!read_sint32(&delta, cursor, end)) return false;
  if (delta < -(int32_t) UINT20_MAX || delta > (int32_t) UINT20_MAX) return false;
  int32_t value = (int32_t) previous_value.value + delta;
  if (value < 0 || value > (int32_t) UINT20_MAX) return false;
  *current_value = (uint20_t) {.value = (unsigned int) value};
  return true;
}

size_t miteruby_compressed_deltas_max_size_of(uint16_t count_of_values) {
  // As per note on the header: uint20_t always fits within 3 bytes
  return (size_t) count_of_values * 3;
}
