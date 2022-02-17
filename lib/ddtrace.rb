# Load tracing
require 'datadog/tracing'

# Load tracing extensions
require 'datadog/tracing/contrib'
require 'datadog/tracing/contrib/extensions'
require 'datadog/opentelemetry/extensions'

# Load appsec
require 'datadog/appsec/autoload' # TODO: datadog/appsec?

# Global namespace that includes all Datadog functionality.
# @public_api
module Datadog
  # Load built-in Datadog integrations
  Tracing::Contrib::Extensions.extend!

  # Load and extend OpenTelemetry compatibility by default
  extend OpenTelemetry::Extensions
end

# Load other products (must follow tracing)
require 'datadog/profiling'
require 'datadog/ci'
