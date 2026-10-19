#pragma once

#include <ruby.h>

#include "buffer.h"

// Requires the main ractor's GVL and exclusive consumer access; must not be called recursively.
void miteruby_miniconsumer_consume(miteruby_buffer_t *buffer, VALUE recorder_instance);
