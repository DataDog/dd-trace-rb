# frozen_string_literal: true

require_relative 'core'
require_relative 'tracing'
require_relative 'tracing/contrib'

module Datadog
  # Namespace for Datadog CI instrumentation:
  # e.g. rspec, cucumber, etc...
  module CI
  end
end

# Integrations
require_relative 'ci/contrib/cucumber/integration'
require_relative 'ci/contrib/rspec/integration'
require_relative 'ci/contrib/minitest/integration'

# Extensions
require_relative 'ci/extensions'
Datadog::CI::Extensions.activate!
