# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      # === INTERNAL USAGE ONLY ===
      #
      # Report telemetry logs via delegating to the telemetry component instance via mutex.
      #
      # IMPORTANT: Invoking this method during the lifecycle of component initialization will
      # be no-op instead.
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
            # `allow_initialization: false` would avoid referencing the components via `safely_synchronize` (mutex)
            # which could cause deadlock during components initialization.
            components = Datadog.send(:components, allow_initialization: false)

            if components && components.telemetry
              components.telemetry
            else
              Datadog.logger.warn(
                'Fail to send telemetry log before components initialization or within components lifecycle'
              )
              nil
            end
          end
        end
      end
    end
  end
end
