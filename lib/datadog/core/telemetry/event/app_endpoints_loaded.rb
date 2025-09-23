# frozen_string_literal: true

require_relative 'base'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry event class for sending 'app-endpoints' payload
        class AppEndpointsLoaded < Base
          def initialize(endpoints, is_initial:)
            @endpoints = endpoints
            @is_initial = !!is_initial
          end

          def type
            'app-endpoints'
          end

          def payload
            {
              is_first: @is_initial,
              endpoints: @endpoints
            }
          end
        end
      end
    end
  end
end
