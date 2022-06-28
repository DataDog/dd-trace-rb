# typed: strict

# Entrypoint file for auto instrumentation.
#
# This file's path is part of the @public_api.
require 'ddtrace'
require 'datadog/tracing/contrib/auto_instrument'

Datadog::Profiling.start_if_enabled

module Datadog
  module AutoInstrument
    LOADED = true
  end
end
