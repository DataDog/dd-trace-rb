# typed: strict

# Load tracing
require 'datadog/tracing'
require 'datadog/tracing/contrib'

# Load appsec
require 'datadog/appsec/autoload' # TODO: datadog/appsec?

# Load other products (must follow tracing)
require 'datadog/profiling'
require 'datadog/ci'
require 'datadog/kit'
