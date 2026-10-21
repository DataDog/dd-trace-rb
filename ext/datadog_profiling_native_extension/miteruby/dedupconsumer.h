#pragma once

#include <ruby.h>

#include "buffer.h"

void miteruby_dedupconsumer_init(void);

// Requires the main ractor's GVL on entry and exclusive consumer access throughout the loop.
// Sleeps without the GVL between drains; Ruby interruption exits the loop and unblocks SIGPROF.
void miteruby_dedupconsumer_consume_loop(miteruby_buffer_t *buffer, VALUE recorder_instance);

// Requires the main ractor's GVL and exclusive consumer access; must not be called recursively.
void miteruby_dedupconsumer_consume(miteruby_buffer_t *buffer, VALUE recorder_instance);

// Requires the main ractor's GVL throughout; must not run concurrently with consume or init.
void miteruby_dedupconsumer_prepare_serialize(VALUE recorder_instance);
