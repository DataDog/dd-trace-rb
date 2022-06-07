# typed: true

require 'datadog/core/telemetry/schemas/common/v1/dependency'
require 'datadog/core/telemetry/schemas/common/v1/integration'
require 'datadog/tracing/contrib'
require 'datadog/tracing/contrib/extensions'

module Datadog
  module Core
    module Telemetry
      # Module defining methods for collecting metadata
      module Collector
        module_function

        def list_dependencies
          Gem::Specification.map { |gem| Telemetry::Schemas::Common::V1::Dependency.new(gem.name, gem.version, gem.hash) }
        end

        def list_integrations
          integrations = Datadog.configuration.tracing.instrumented_integrations
          integrations.map do |name, integration|
            patch_result = integration.patch
            Telemetry::Schemas::Common::V1::Integration
              .new(name, patch_result == true, integration.class.version, nil,
                   (patch_result == true ? true : patch_result[:compatible]),
                   (patch_result != true ? integration_error(patch_result) : nil))
          end
        end

        def integration_error(patch_result)
          desc = "Available?: #{patch_result[:available]}"
          desc += ", Loaded? #{patch_result[:loaded]}"
          desc += ", Compatible? #{patch_result[:compatible]}"
          desc += ", Patchable? #{patch_result[:patchable]}"
          desc
        end
      end
    end
  end
end
