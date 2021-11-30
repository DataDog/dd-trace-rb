require 'ddtrace/tagging/analytics'
require 'ddtrace/tagging/metadata'

module Datadog
  # Adds common tagging behavior
  module Tagging
    def self.included(base)
      base.include(Tagging::Metadata)

      # Additional extensions
      base.prepend(Tagging::Analytics)
    end
  end
end
