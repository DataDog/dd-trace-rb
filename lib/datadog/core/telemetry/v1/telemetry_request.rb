require 'datadog/core/telemetry/utils/validation'
require 'datadog/core/telemetry/v1/app_started'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/host'

module Datadog
  module Core
    module Telemetry
      module V1
        # Describes attributes for telemetry API request
        class TelemetryRequest
          include Telemetry::Utils::Validation

          API_VERSIONS = ['v1'].freeze
          REQUEST_TYPES = ['app-started'].freeze
          PAYLOAD_TYPES = [Telemetry::V1::AppStarted].freeze
          ERROR_BAD_API_VERSION_MESSAGE = ":api_version must be one of #{API_VERSIONS}".freeze
          ERROR_BAD_APPLICATION_MESSAGE = ':application must be of type Application'.freeze
          ERROR_BAD_DEBUG_MESSAGE = ':debug must be of type Boolean'.freeze
          ERROR_BAD_HOST_MESSAGE = ':host must be a non-empty String'.freeze
          ERROR_BAD_PAYLOAD_MESSAGE = ":payload type must be one of #{PAYLOAD_TYPES}".freeze
          ERROR_BAD_REQUEST_TYPE_MESSAGE = ":request_type must be one of #{REQUEST_TYPES}".freeze
          ERROR_BAD_RUNTIME_ID_MESSAGE = ':runtime_id must be a non-empty String'.freeze
          ERROR_BAD_SEQ_ID_MESSAGE = ':seq_id must be of type Integer'.freeze
          ERROR_BAD_SESSION_ID_MESSAGE = ':session_id must be of type String'.freeze
          ERROR_BAD_TRACER_TIME_MESSAGE = ':tracer_time must be of type Integer'.freeze

          attr_reader \
            :api_version,
            :application,
            :debug,
            :host,
            :payload,
            :request_type,
            :runtime_id,
            :seq_id,
            :session_id,
            :tracer_time

          # @param api_version [String] Requested API version, `v1`
          # @param application [Telemetry::V1::Application] Object that contains information about the environment of the
          #   application
          # @param host [Telemetry::V1::Host] Object that holds host related information
          # @param payload [Telemetry::V1::AppStarted] The payload of the request, type impacted by :request_type
          # @param request_type [String] Requested API function impacting the Payload type, `app-started`
          # @param runtime_id [String] V4 UUID that represents a tracer session
          # @param seq_id [Integer] Counter that should be auto incremented every time an API call is being made
          # @param tracer_time [Integer] Unix timestamp (in seconds) of when the message is being sent
          # @param debug [Boolean] Flag that enables payload debug mode
          # @param session_id [String] V4 UUID that represents the session of the top level tracer process, often same\
          #   as runtime_id
          def initialize(api_version:, application:, host:, payload:, request_type:, runtime_id:, seq_id:, tracer_time:,
                         debug: nil, session_id: nil)
            validate(api_version: api_version, application: application, host: host, payload: payload,
                     request_type: request_type, runtime_id: runtime_id, seq_id: seq_id, tracer_time: tracer_time,
                     debug: debug, session_id: session_id)
            @api_version = api_version
            @application = application
            @debug = debug
            @host = host
            @payload = payload
            @request_type = request_type
            @runtime_id = runtime_id
            @seq_id = seq_id
            @session_id = session_id
            @tracer_time = tracer_time
          end

          private

          # Validates all arguments passed to the class on initialization
          #
          # @!visibility private
          def validate(api_version:, application:, debug:, host:, payload:, request_type:, runtime_id:, seq_id:,
                       session_id:, tracer_time:)
            unless valid_string?(api_version) && API_VERSIONS.include?(api_version)
              raise ArgumentError,
                    ERROR_BAD_API_VERSION_MESSAGE
            end
            raise ArgumentError, ERROR_BAD_APPLICATION_MESSAGE unless application.is_a?(Telemetry::V1::Application)
            raise ArgumentError, ERROR_BAD_DEBUG_MESSAGE unless valid_optional_bool?(debug)
            raise ArgumentError, ERROR_BAD_HOST_MESSAGE unless host.is_a?(Telemetry::V1::Host)
            raise ArgumentError, ERROR_BAD_PAYLOAD_MESSAGE unless PAYLOAD_TYPES.include?(payload.class)
            raise ArgumentError, ERROR_BAD_REQUEST_TYPE_MESSAGE unless REQUEST_TYPES.include?(request_type)
            raise ArgumentError, ERROR_BAD_RUNTIME_ID_MESSAGE unless valid_string?(runtime_id)
            raise ArgumentError, ERROR_BAD_SEQ_ID_MESSAGE unless valid_int?(seq_id)
            raise ArgumentError, ERROR_BAD_SESSION_ID_MESSAGE unless valid_optional_string?(session_id)
            raise ArgumentError, ERROR_BAD_TRACER_TIME_MESSAGE unless valid_int?(tracer_time)
          end
        end
      end
    end
  end
end
