# frozen_string_literal: true

require_relative 'base'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry class for the 'app-extended-heartbeat' event
        class AppExtendedHeartbeat < Base
          def initialize(configuration:)
            @configuration = configuration
          end

          def type
            'app-extended-heartbeat'
          end

          def payload
            {
              configuration: @configuration,
            }
          end
        end
      end
    end
  end
end
