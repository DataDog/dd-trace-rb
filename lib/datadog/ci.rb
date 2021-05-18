require 'ddtrace'

module Datadog
  # Namespace for Datadog CI instrumentation:
  # e.g. rspec, cucumber, etc...
  module CI
  end
end

require 'datadog/ci/contrib/cucumber/integration'
require 'datadog/ci/contrib/rspec/integration'
