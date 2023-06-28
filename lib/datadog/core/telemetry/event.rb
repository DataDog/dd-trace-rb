require_relative 'collector'
require_relative 'v1/app_event'
require_relative 'v1/telemetry_request'

module Datadog
  module Core
    module Telemetry
      # Class defining methods to construct a Telemetry event
      class Event
        include Telemetry::Collector

        API_VERSION = 'v1'.freeze

        attr_reader \
          :api_version

        def initialize
          @api_version = API_VERSION
        end

        # Forms a TelemetryRequest object based on the event request_type
        # @param request_type [String] the type of telemetry request to collect data for
        # @param seq_id [Integer] the ID of the request; incremented each time a telemetry request is sent to the API
        def telemetry_request(request_type:, seq_id:)
          Telemetry::V1::TelemetryRequest.new(
            api_version: @api_version,
            application: application,
            host: host,
            payload: payload(request_type),
            request_type: request_type,
            runtime_id: runtime_id,
            seq_id: seq_id,
            tracer_time: tracer_time,
          )
        end

        private

        def payload(request_type)
          case request_type
          when :'app-started'
            app_started
          when :'app-closing', :'app-heartbeat'
            {}
          when :'app-integrations-change'
            app_integrations_change
          else
            raise ArgumentError, "Request type invalid, received request_type: #{@request_type}"
          end
        end

        def app_started
          Telemetry::V1::AppEvent.new(
            dependencies: dependencies,
            integrations: integrations,
            configuration: configurations,
            additional_payload: additional_payload
          )
        end

        def app_integrations_change
          Telemetry::V1::AppEvent.new(integrations: integrations)
        end
      end
    end
  end
end
