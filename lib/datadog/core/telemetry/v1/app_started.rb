module Datadog
  module Core
    module Telemetry
      module V1
        # Describes payload for telemetry V1 API app_started event
        class AppStarted
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
            @additional_payload = additional_payload
            @configuration = configuration
            @dependencies = dependencies
            @integrations = integrations
          end
        end
      end
    end
  end
end
