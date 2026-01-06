# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Karafka
        # Karafka framework code, used to essentially:
        # - handle configuration entries which are specific to Datadog tracing
        # - instrument parts of the framework when needed
        module Framework
          def self.setup
            karafka_configurations = Datadog.configuration.tracing.fetch_integration(:karafka).configurations

            Datadog.configure do |datadog_config|
              karafka_configurations.each do |config_name, karafka_config|
                activate_waterdrop!(datadog_config, config_name, karafka_config)
              end
            end
          end

          # Apply relevant configuration from Karafka to WaterDrop
          def self.activate_waterdrop!(datadog_config, config_name, karafka_config)
            datadog_config.tracing.instrument(
              :waterdrop,
              enabled: karafka_config[:enabled],
              service_name: karafka_config[:service_name],
              distributed_tracing: karafka_config[:distributed_tracing],
              describes: config_name,
            )
          end
        end
      end
    end
  end
end
