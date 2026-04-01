# frozen_string_literal: true

require_relative 'app_started'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry class for the 'app-extended-heartbeat' event.
        # Inherits AppStarted to reuse its configuration-building logic,
        # computing fresh configuration at heartbeat time so remote config
        # changes are reflected.
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
