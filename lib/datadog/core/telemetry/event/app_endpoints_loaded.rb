# frozen_string_literal: true

require_relative 'base'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry event class for sending 'app-endpoints' payload
        class AppEndpointsLoaded < Base
          ENDPOINT_COLLECTION_MESSAGE_LIMIT = 300

          def initialize(serialized_endpoints)
            @serialized_endpoints = serialized_endpoints
          end

          def type
            'app-endpoints'
          end

          def payload
            # TODO: add pagination
            {
              is_first: 'TODO', # a boolean indicating that the information is being sent for the first time, or is a first page
              endpoints: serialized_endpoints
            }
          end
        end
      end
    end
  end
end
