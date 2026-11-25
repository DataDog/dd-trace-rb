#pragma once

#include "datadog_ruby_common.h"

// Defines `Datadog::Core::Transport::HTTP::Adapters::Native::Client`.
// Does nothing when libdatadog was built without the `http-client` feature (no `HAVE_DDOG_HTTP_CLIENT_NEW`).
void http_client_init(VALUE core_module);
