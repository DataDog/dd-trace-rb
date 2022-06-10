require 'datadog/core/telemetry/utils/validation'
require 'datadog/core/telemetry/v1/configuration'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/integration'

module Datadog
  module Core
    module Telemetry
      module V1
        # Describes payload for telemetry V1 API app_started event
        class AppStarted
          include Telemetry::Utils::Validation

          ERROR_NIL_ARGUMENTS =
            'One of :additional_payload, :configuration, :dependencies or :integrations must not be nil'.freeze
          ERROR_BAD_ADDITIONAL_PAYLOAD_MESSAGE = ':additional_payload must be of type Array[Configuration]'.freeze
          ERROR_BAD_CONFIGURATION_MESSAGE = ':configuration must be of type Array[Configuration]'.freeze
          ERROR_BAD_DEPENDENCIES_MESSAGE = ':dependencies must be of type Array[Dependency]'.freeze
          ERROR_BAD_INTEGRATIONS_MESSAGE = ':integrations must be of type Array[Integration]'.freeze

          attr_reader \
            :additional_payload,
            :configuration,
            :dependencies,
            :integrations

          # @param additional_payload [Array<Telemetry::V1::Configuration>] List of Additional payload to track (any key
          #   value not mentioned and doesn't fit under a metric)
          # @param configuration [Array<Telemetry::V1::Configuration>] List of Tracer related configuration data
          # @param dependencies [Array<Telemetry::V1::Dependency>] List of all loaded modules requested by the app
          # @param integrations [Array<Telemetry::V1::Integration>] List of integrations that are available within the app
          #   and applicable to be traced
          def initialize(additional_payload: nil, configuration: nil, dependencies: nil, integrations: nil)
            validate(additional_payload: additional_payload, configuration: configuration, dependencies: dependencies,
                     integrations: integrations)
            @additional_payload = additional_payload
            @configuration = configuration
            @dependencies = dependencies
            @integrations = integrations
          end

          private

          # Validates all arguments passed to the class on initialization
          #
          # @!visibility private
          def validate(additional_payload:, configuration:, dependencies:, integrations:)
            if additional_payload.nil? && configuration.nil? && dependencies.nil? && integrations.nil?
              raise ArgumentError, ERROR_NIL_ARGUMENTS
            end
            if additional_payload && !type_of_array?(
              additional_payload, Telemetry::V1::Configuration
            )
              raise ArgumentError, ERROR_BAD_ADDITIONAL_PAYLOAD_MESSAGE
            end
            if configuration && !type_of_array?(
              configuration, Telemetry::V1::Configuration
            )
              raise ArgumentError, ERROR_BAD_CONFIGURATION_MESSAGE
            end
            if dependencies && !type_of_array?(
              dependencies, Telemetry::V1::Dependency
            )
              raise ArgumentError, ERROR_BAD_DEPENDENCIES_MESSAGE
            end
            if integrations && !type_of_array?(
              integrations, Telemetry::V1::Integration
            )
              raise ArgumentError, ERROR_BAD_INTEGRATIONS_MESSAGE
            end
          end
        end
      end
    end
  end
end
