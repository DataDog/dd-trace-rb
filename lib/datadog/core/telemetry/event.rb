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
        include Telemetry::Utils::Validation

        API_VERSION = 'v1'.freeze
        ERROR_BAD_REQUEST_TYPE = ':request_type must be a non-empty String'.freeze
        ERROR_BAD_SEQ_ID = ':seq_id must be a non-empty Integer'.freeze
        ERROR_BAD_API_VERSION = ':api_version must be of type String'.freeze

        attr_reader \
          :request_type,
          :seq_id,
          :api_version

        # @param request_type [String] the type of telemetry request to collect data for
        # @param seq_id [Integer] the ID to attach to the request, incremented for each new telemetry request
        # @param api_version [String] telemetry API version to request; defaults to `v1`
        def initialize(request_type:, seq_id:, api_version: API_VERSION)
          validate(request_type, seq_id, api_version)
          @request_type = request_type
          @seq_id = seq_id
          @api_version = api_version
        end

        # Forms a TelemetryRequest object based on the event @request_type
        def request
          case @request_type
          when 'app-started'
            payload = app_started
          else
            raise ArgumentError, "Request type invalid, received request_type: #{@request_type}"
          end
          telemetry_request(payload)
        end

        private

        def validate(request_type, seq_id, api_version)
          raise ArgumentError, ERROR_BAD_REQUEST_TYPE unless valid_string?(request_type)
          raise ArgumentError, ERROR_BAD_SEQ_ID unless valid_int?(seq_id)
          raise ArgumentError, ERROR_BAD_API_VERSION unless valid_string?(api_version)
        end

        def telemetry_request(payload)
          Telemetry::V1::TelemetryRequest.new(
            api_version: @api_version,
            application: application,
            host: host,
            payload: payload,
            request_type: @request_type,
            runtime_id: runtime_id,
            seq_id: @seq_id,
            tracer_time: tracer_time,
          )
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
