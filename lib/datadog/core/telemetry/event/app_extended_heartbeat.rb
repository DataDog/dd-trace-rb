# frozen_string_literal: true

require_relative 'app_started'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry class for the 'app-extended-heartbeat' event
        class AppExtendedHeartbeat < AppStarted
          def initialize(settings:, agent_settings:)
            @configuration = configuration(settings, agent_settings)
          end

          def type
            'app-extended-heartbeat'
          end

          def payload
            {
              configuration: @configuration,
            }
          end

          def app_started?
            false
          end
        end
      end
    end
  end
end
