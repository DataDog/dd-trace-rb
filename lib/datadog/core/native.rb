# frozen_string_literal: true

module Datadog
  module Core
    # Namespace for native extension related code
    # Exception classes are defined here and used by C extensions
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

      # Common exception classes for native extension errors
      class RuntimeError < ::RuntimeError
        prepend(Native::Error)
      end

      # Common exception classes for native extension errors
      class ArgumentError < ::ArgumentError
        prepend(Native::Error)
      end

      # Common exception classes for native extension errors
      class TypeError < ::TypeError
        prepend(Native::Error)
      end
    end
  end
end
