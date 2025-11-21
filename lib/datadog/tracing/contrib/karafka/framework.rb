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
            Datadog.configure do |datadog_config|
              karafka_config = datadog_config.tracing[:karafka]
              activate_waterdrop!(datadog_config, karafka_config)
            end
          end

          # Apply relevant configuration from Karafka to WaterDrop
          def self.activate_waterdrop!(datadog_config, karafka_config)
            datadog_config.tracing.instrument(
              :waterdrop,
              service_name: karafka_config[:service_name],
              distributed_tracing: karafka_config[:distributed_tracing],
            )
          end
        end
      end
    end
  end
end
