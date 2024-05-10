# frozen_string_literal: true

module Datadog
  module Debugger
    # Core-pluggable component for Debugger
    class Component
      class << self
        def build(settings)
          return unless settings.respond_to?(:debugger) && settings.debugger.enabled

          new
        end
      end

      def shutdown!(replacement = nil)
      end
    end
  end
end
