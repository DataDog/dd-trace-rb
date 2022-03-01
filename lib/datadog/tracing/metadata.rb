# typed: true

require 'datadog/tracing/metadata/analytics'
require 'datadog/tracing/metadata/tagging'

module Datadog
  module Tracing
    # Adds common tagging behavior
    module Metadata
      def self.included(base)
        base.include(Metadata::Tagging)

        # Additional extensions
        base.prepend(Metadata::Analytics)
      end
    end
  end
end
