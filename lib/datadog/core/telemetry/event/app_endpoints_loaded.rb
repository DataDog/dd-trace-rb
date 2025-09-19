# frozen_string_literal: true

require_relative 'base'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry event class for sending 'app-endpoints' payload
        class AppEndpointsLoaded < Base
          def initialize(serialized_endpoints)
            @serialized_endpoints = serialized_endpoints
          end

          def type
            'app-endpoints'
          end

          def payload(is_first: false)
            {
              is_first: is_first,
              endpoints: @serialized_endpoints
            }
          end
        end
      end
    end
  end
end
