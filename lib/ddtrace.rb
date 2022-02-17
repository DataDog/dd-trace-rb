# Load tracing
require 'datadog/tracing'
require 'datadog/tracing/contrib'
require 'datadog/opentelemetry/extensions'

# Load appsec
require 'datadog/appsec/autoload' # TODO: datadog/appsec?

# Load other products (must follow tracing)
require 'datadog/profiling'
require 'datadog/ci'
