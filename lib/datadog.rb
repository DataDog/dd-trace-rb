# frozen_string_literal: true

# Load tracing
require_relative 'datadog/tracing'
require_relative 'datadog/tracing/contrib'

# Load other products (must follow tracing)
require_relative 'datadog/profiling'
require_relative 'datadog/appsec'
# Line probes will not work on Ruby < 2.6 because of lack of :script_compiled
# trace point. Only load DI on supported Ruby versions.
require_relative 'datadog/di' if RUBY_VERSION >= '2.6'
require_relative 'datadog/kit'
