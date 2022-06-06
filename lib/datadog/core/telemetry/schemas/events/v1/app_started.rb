module Datadog
  module Core
    module Telemetry
      module Schemas
        module Events
          module V1
            # Describes payload for telemetry V1 API app_started event
            class AppStarted
              attr_reader :configuration, :dependencies, :integrations, :additional_payload

              def initialize(configuration = nil, dependencies = nil, integrations = nil, additional_payload = nil)
                @configuration = configuration
                @dependencies = dependencies
                @integrations = integrations
                @additional_payload = additional_payload
              end
            end
          end
        end
      end
    end
  end
end
