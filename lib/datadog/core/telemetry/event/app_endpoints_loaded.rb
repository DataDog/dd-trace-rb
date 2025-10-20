# frozen_string_literal: true

require_relative 'base'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry event class for sending 'app-endpoints' payload
        class AppEndpointsLoaded < Base
          def initialize(endpoints, is_first:)
            @endpoints = endpoints
            @is_first = !!is_first
          end

          def type
            'app-endpoints'
          end

          def payload
            {
              is_first: @is_first,
              endpoints: @endpoints
            }
          end
        end
      end
    end
  end
end
