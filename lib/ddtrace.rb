# typed: strict

# Load logging before tracing as trace <> log correlation,
# implemented in the tracing component, depends on logging
# data structures.
# Logging is also does not depend on other products.
require 'datadog/logging'

# Load tracing
require 'datadog/tracing'
require 'datadog/tracing/contrib'

# Load appsec
require 'datadog/appsec/autoload' # TODO: datadog/appsec?

# Load other products (must follow tracing)
require 'datadog/profiling'
require 'datadog/ci'

# Load higher level APIs, which depend on the products loaded above
require 'datadog/kit'
