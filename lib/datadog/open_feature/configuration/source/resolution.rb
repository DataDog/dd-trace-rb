# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Configuration
      module Source
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
