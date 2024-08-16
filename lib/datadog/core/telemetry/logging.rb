# frozen_string_literal: true

require_relative 'event'

module Datadog
  module Core
    module Telemetry
      # Logging interface for sending telemetry logs.
      #
      # Reporting internal error so that we can fix them.
      # IMPORTANT: Make sure to not log any sensitive information.
      module Logging
        module_function

        def report(exception, level:)
          # Annoymous exceptions to be logged as <Class:0x00007f8b1c0b3b40>
          message = exception.class.name || exception.class.inspect

          event = Event::Log.new(
            message: message,
            level: level
          )

          if (telemetry = Datadog.send(:components).telemetry)
            telemetry.log!(event)
          else
            Datadog.logger.debug do
              "Attempting to send telemetry log when telemetry component is not ready: #{message}"
            end
          end
        end
      end
    end
  end
end
