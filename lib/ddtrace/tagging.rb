require 'ddtrace/tagging/analytics'
require 'ddtrace/tagging/manual_tracing'
require 'ddtrace/tagging/metadata'

module Datadog
  # Adds common tagging behavior
  module Tagging
    def self.included(base)
      base.include(Tagging::Metadata)

      # Additional extensions
      base.prepend(Tagging::Analytics)
      base.prepend(Tagging::ManualTracing)
    end
  end
end
