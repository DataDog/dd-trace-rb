module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Events
            # Describes payload for telemetry V1 API app_started event
            class AppStarted
              attr_reader \
                :additional_payload,
                :configuration,
                :dependencies,
                :integrations

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
  end
end
