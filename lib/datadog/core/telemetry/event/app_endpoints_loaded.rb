# frozen_string_literal: true

require_relative 'base'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry event class for sending 'app-endpoints' payload
        class AppEndpointsLoaded < Base
          def initialize(serialized_endpoints, is_first_event:)
            @serialized_endpoints = serialized_endpoints
            @is_first_event = !!is_first_event
          end

          def type
            'app-endpoints'
          end

          def payload
            {
              is_first: @is_first_event,
              endpoints: @serialized_endpoints
            }
          end
        end
      end
    end
  end
end
