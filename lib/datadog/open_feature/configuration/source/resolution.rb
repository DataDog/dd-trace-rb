# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Configuration
      module Source
        # Resolved Feature Flags enablement and delivery source.
        class Resolution
          attr_reader :source

          def initialize(enabled:, source:)
            @enabled = enabled
            @source = source
          end

          def enabled?
            @enabled
          end
        end
      end
    end
  end
end
