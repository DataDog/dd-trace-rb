# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      # Module for sending telemetry logs to the global telemetry instance
      module Logger
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
end
