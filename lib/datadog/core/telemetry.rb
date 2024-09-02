# frozen_string_literal: true

module Datadog
  module Core
    # Telemetry module for sending telemetry events
    module Telemetry
      class << self
        def report(exception, level: :error, description: nil)
          instance&.report(exception, level: level, description: description)
        end

        def error(description)
          instance&.error(description)
        end

        private

        def instance
          Datadog.send(:components).telemetry
        end
      end
    end
  end
end
