#pragma once


// We write miteruby files as if the miteruby unity build did not exist: e.g. if you need a function in a miteruby
// .c file that's defined in another miteruby .c file, we don't mark that function as static in the source directly.
//
// And if a function is local to its .c file, we mark it as static.
//
// Because the unity build compiles everything together, a static function can still be called from another miteruby
// .c file. Everything internal could be static. But then we'd lose the
// "oh this is used elsewhere in miteruby" visual cue, and that's valuable to us. Furthermore, it keeps the door open
// for a trivial non-unity build.
//
// So we introduced MITERUBY_INTERNAL as a marker for "it's used elsewhere in miteruby, but nowhere outside of it".
//
// This marker is key in another optimization: Non-static functions are kept by the compiler available
// to outside callers of miteruby. That's not great for functions we know are internal to miteruby because we might miss compiler optimizations and simplifications --
// exactly the reason why the unity build exists.
//
// So for the unity build we set MITERUBY_INTERNAL to static. This way in code inspection we can quickly see three variants
// * Function is static => only used in the .c that defines it
// * Function is MITERUBY_INTERNAL => it's used elsewhere in miteruby, but doesn't escape outside it/the unity build
// * Function is not static and not MITERUBY_INTERNAL => it's being exposed to being called outside of miteruby
#define MITERUBY_INTERNAL static

#include "miteruby/can_overflow.h"
#include "miteruby/raw_events_queue.h"
#include "miteruby/consumer.h"
#include "miteruby/sample_event.h"
