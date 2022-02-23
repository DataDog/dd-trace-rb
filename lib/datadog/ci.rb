# typed: false
require 'datadog/core'
require 'datadog/tracing'
require 'datadog/tracing/contrib'

module Datadog
  # Namespace for Datadog CI instrumentation:
  # e.g. rspec, cucumber, etc...
  module CI
  end
end

# Integrations
require 'datadog/ci/contrib/cucumber/integration'
require 'datadog/ci/contrib/rspec/integration'

# Extensions
require 'datadog/ci/extensions'
Datadog::CI::Extensions.activate!
