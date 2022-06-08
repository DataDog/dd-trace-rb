# typed: true

require 'datadog/core/telemetry/schemas/v1/base/dependency'
require 'datadog/core/telemetry/schemas/v1/base/integration'
require 'datadog/core/telemetry/schemas/v1/base/application'
require 'datadog/core/telemetry/schemas/v1/base/host'
require 'datadog/core/environment/ext'

module Datadog
  module Core
    module Telemetry
      # Module defining methods for collecting metadata
      module Collector
        module_function

        def dependencies
          Gem::Specification.map { |gem| Telemetry::Schemas::V1::Base::Dependency.new(gem.name, gem.version, gem.hash) }
        end

        def integrations
          integrations = Datadog.configuration.tracing.instrumented_integrations
          integrations.map do |name, integration|
            patch_result = integration.patch
            Telemetry::Schemas::V1::Base::Integration
              .new(name: name, enabled: (patch_result == true), version: integration.class.version,
                   compatible: (patch_result == true ? true : patch_result[:compatible]),
                   error: (patch_result != true ? integration_error(patch_result) : nil))
          end
        end

        def integration_error(patch_result)
          desc = "Available?: #{patch_result[:available]}"
          desc += ", Loaded? #{patch_result[:loaded]}"
          desc += ", Compatible? #{patch_result[:compatible]}"
          desc += ", Patchable? #{patch_result[:patchable]}"
          desc
        end

        def application
          Telemetry::Schemas::V1::Base::Application
            .new(Datadog::Core::Environment::Ext::LANG,
                 Datadog::Core::Environment::Ext::LANG_VERSION,
                 Datadog::Core::Environment::Ext::ENV_SERVICE,
                 Datadog::Core::Environment::Ext::TRACER_VERSION,
                 Datadog::Core::Environment::Ext::ENV_ENVIRONMENT,
                 Datadog::Core::Environment::Ext::RUBY_ENGINE,
                 nil,
                 Datadog::Core::Environment::Ext::ENGINE_VERSION,
                 Datadog::Core::Environment::Ext::ENV_VERSION,
                 nil
            )
        end

        def host
        end
      end
    end
  end
end
