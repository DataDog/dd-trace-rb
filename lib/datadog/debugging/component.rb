# frozen_string_literal: true

module Datadog
  module Debugging
    # Core-pluggable component for Debugging
    class Component
      class << self
        def build(settings)
          return unless settings.respond_to?(:debugging) && settings.debugging.enabled

          new
        end
      end

      def shutdown!(replacement = nil); end
    end
  end
end
