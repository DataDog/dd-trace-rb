# typed: true

require 'datadog/core/telemetry/collector'
require 'datadog/core/telemetry/v1/app_started'
require 'datadog/core/telemetry/v1/telemetry_request'

module Datadog
  module Core
    module Telemetry
      # Class defining methods to construct a Telemetry event
      class Event
        include Kernel

        include Telemetry::Collector

        API_VERSION = 'v1'.freeze
        ERROR_BAD_API_VERSION = ':api_version must not be nil'.freeze

        attr_reader \
          :request_type,
          :api_version

        attr_accessor \
          :seq_id

        # @param api_version [String] telemetry API version to request; defaults to `v1`
        def initialize(api_version: API_VERSION)
          raise ArgumentError, ERROR_BAD_API_VERSION if api_version.nil?

          @seq_id = 1
          @api_version = api_version
        end

        # Forms a TelemetryRequest object based on the event request_type
        # @param request_type [String] the type of telemetry request to collect data for
        def telemetry_request(request_type:)
          Telemetry::V1::TelemetryRequest.new(
            api_version: @api_version,
            application: application,
            host: host,
            payload: payload(request_type),
            request_type: request_type,
            runtime_id: runtime_id,
            seq_id: @seq_id,
            tracer_time: tracer_time,
          )
        end

        private

        def payload(request_type)
          case request_type
          when 'app-started'
            app_started
          else
            raise ArgumentError, "Request type invalid, received request_type: #{@request_type}"
          end
        end

        def app_started
          Telemetry::V1::AppStarted.new(
            dependencies: dependencies,
            integrations: integrations,
            configuration: configurations
          )
        end
      end
    end
  end
end
