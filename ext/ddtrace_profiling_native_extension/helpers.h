#pragma once

// Used to mark symbols to be exported to the outside of the extension.
// Consider very carefully before tagging a function with this.
#define DDTRACE_EXPORT __attribute__ ((visibility ("default")))
