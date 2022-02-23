# typed: strict
# Load tracing
require 'datadog/tracing'

# Load tracing extensions
require 'datadog/tracing/contrib'
require 'datadog/tracing/contrib/auto_instrument'
require 'datadog/tracing/contrib/extensions'
require 'datadog/opentelemetry/extensions'
require 'ddtrace/auto_instrument_base'

# Load appsec
require 'datadog/appsec/autoload' # TODO: datadog/appsec?

# Global namespace that includes all Datadog functionality.
# @public_api
module Datadog
  extend AutoInstrumentBase

  # Load built-in Datadog integrations
  Tracing::Contrib::Extensions.extend!

  # Load Contrib auto instrumentation
  extend Tracing::Contrib::AutoInstrument

  # Load and extend OpenTelemetry compatibility by default
  extend OpenTelemetry::Extensions
end

# Load other products (must follow tracing)
require 'datadog/profiling'
require 'datadog/ci'
