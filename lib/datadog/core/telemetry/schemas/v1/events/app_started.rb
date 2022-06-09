require 'datadog/core/telemetry/schemas/utils/validation'
require 'datadog/core/telemetry/schemas/v1/base/configuration'
require 'datadog/core/telemetry/schemas/v1/base/dependency'
require 'datadog/core/telemetry/schemas/v1/base/integration'

module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Events
            # Describes payload for telemetry V1 API app_started event
            class AppStarted
              include Schemas::Utils::Validation

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

              def initialize(additional_payload: nil, configuration: nil, dependencies: nil, integrations: nil)
                validate(additional_payload: additional_payload, configuration: configuration, dependencies: dependencies,
                         integrations: integrations)
                @additional_payload = additional_payload
                @configuration = configuration
                @dependencies = dependencies
                @integrations = integrations
              end

              private

              def validate(additional_payload:, configuration:, dependencies:, integrations:)
                if additional_payload.nil? && configuration.nil? && dependencies.nil? && integrations.nil?
                  raise ArgumentError, ERROR_NIL_ARGUMENTS
                end
                if additional_payload && !type_of_array?(
                  additional_payload, Base::Configuration
                )
                  raise ArgumentError, ERROR_BAD_ADDITIONAL_PAYLOAD_MESSAGE
                end
                if configuration && !type_of_array?(
                  configuration, Base::Configuration
                )
                  raise ArgumentError, ERROR_BAD_CONFIGURATION_MESSAGE
                end
                if dependencies && !type_of_array?(
                  dependencies, Base::Dependency
                )
                  raise ArgumentError, ERROR_BAD_DEPENDENCIES_MESSAGE
                end
                if integrations && !type_of_array?(
                  integrations, Base::Integration
                )
                  raise ArgumentError, ERROR_BAD_INTEGRATIONS_MESSAGE
                end
              end
            end
          end
        end
      end
    end
  end
end
