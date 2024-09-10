# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      # === INTRENAL USAGE ONLY ===
      #
      # Report telemetry logs via delegating to the telemetry component instance via mutex.
      #
      # IMPORTANT: Invoking this method during the lifecycle of component initialization will
      # cause a non-recoverable deadlock
      #
      # For developer using this module:
      #   read: lib/datadog/core/telemetry/logging.rb
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
