# frozen_string_literal: true

module Datadog
  module Core
    module Native
      # Base error type for exceptions raised by our native extensions.
      # These errors have both the original error message and a telemetry-safe message.
      # The telemetry-safe message is statically defined and does not possess dynamic data.
      module Error
        attr_reader :telemetry_message

        def initialize(message, telemetry_message = nil)
          super(message)
          @telemetry_message = telemetry_message
        end
      end

      # Common exception class for native extension runtime errors
      class RuntimeError < ::RuntimeError
        prepend(Error)
      end

      # Common exception class for native extension argument errors
      class ArgumentError < ::ArgumentError
        prepend(Error)
      end

      # Common exception class for native extension type errors
      class TypeError < ::TypeError
        prepend(Error)
      end
    end
  end
end
