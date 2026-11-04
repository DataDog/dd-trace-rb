#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#define UINT20_MAX UINT32_C(1048575)

// Using uint20_t guarantees that any value encoded as a delta fits within 3 bytes.
// Check wider inputs against UINT20_MAX before assignment: the bitfield silently truncates them.
typedef struct {
  unsigned int value : 20;
} uint20_t;

// Deltas use protobuf's sint32 payload encoding (ZigZag followed by a base-128 varint), without field tags.
// Starting from zero: values 1, 2, 3, 4 -> deltas +1, +1, +1, +1 -> ZigZag 2, 2, 2, 2 -> bytes 02 02 02 02.
// https://protobuf.dev/programming-guides/encoding/#signed-integers
// The caller tracks the previous value; both operations advance cursor.
// end is one past the buffer. A failed write may advance cursor and leave a partial encoding.
__attribute__((warn_unused_result))
bool miteruby_compressed_deltas_write(uint20_t previous_value, uint20_t current_value, uint8_t **cursor, const uint8_t *end);
// A failed read may advance cursor but leaves current_value unchanged.
__attribute__((warn_unused_result))
bool miteruby_compressed_deltas_read(uint20_t previous_value, uint20_t *current_value, const uint8_t **cursor, const uint8_t *end);

// Maximum amount of bytes that miteruby_compressed_deltas_write will ever need when writing an array of values.
size_t miteruby_compressed_deltas_max_size_of(uint16_t count_of_values);
