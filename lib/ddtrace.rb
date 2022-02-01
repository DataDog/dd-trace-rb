# typed: strict
# TODO: This file currently acts as the root for
#       all Datadog products in this package.
#
#       We want 'ddtrace' to only be concerned with loading
#       tracing. 'datadog' should load all features instead.
#
#       Until we can introduce this package/loader, load all
#       Datadog features here for now, to preserve loading
#       behavior. Later remove this when 'datadog' loads 'ddtrace'.
require 'datadog/core'

# Load tracing
require 'datadog/tracing'
require 'datadog/contrib'
require 'ddtrace/contrib/auto_instrument'
require 'ddtrace/contrib/extensions'
require 'ddtrace/opentelemetry/extensions'
require 'ddtrace/tracer'
require 'ddtrace/pipeline'
require 'ddtrace/auto_instrument_base'

# Global namespace that includes all Datadog functionality.
# @public_api
module Datadog
  extend AutoInstrumentBase

  # Load built-in Datadog integrations
  Contrib::Extensions.extend!
  # Load Contrib auto instrumentation
  extend Contrib::AutoInstrument

  # Load and extend OpenTelemetry compatibility by default
  extend OpenTelemetry::Extensions
end

# Load other products (must follow tracing)
require 'datadog/profiling'
require 'datadog/ci'
