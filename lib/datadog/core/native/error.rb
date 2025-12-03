# frozen_string_literal: true

module Datadog
  module Core
    module Native
      # Base error types for exceptions raised by our native extensions.
      # Native helpers store a telemetry-safe message in the `@telemetry_message`
      # instance variable when raising these exceptions.
      class RuntimeError < ::RuntimeError; end
      class ArgumentError < ::ArgumentError; end
      class TypeError < ::TypeError; end
    end
  end
end
