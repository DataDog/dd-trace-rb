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
        extend self

        def report(exception, level:, description: nil)
          # Annoymous exceptions to be logged as <Class:0x00007f8b1c0b3b40>
          message = +''
          message << (exception.class.name || exception.class.inspect)
          message << ':' << description if description

          event = Event::Log.new(
            message: message,
            level: level
          )

          dispatch(event)
        end

        def error(description)
          event = Event::Log.new(message: description, level: :error)

          dispatch(event)
        end

        private

        def dispatch(event)
          if (telemetry = Datadog.send(:components).telemetry)
            telemetry.log!(event)
          else
            Datadog.logger.debug { 'Attempting to send telemetry log when telemetry component is not ready' }
          end
        end
      end
    end
  end
end
