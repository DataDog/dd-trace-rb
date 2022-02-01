# Load tracing
require 'datadog/tracing'

# Load tracing extensions
require 'datadog/contrib'
require 'ddtrace/contrib/auto_instrument'
require 'ddtrace/contrib/extensions'
require 'datadog/opentelemetry/extensions'
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
