# typed: true

require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/host'
require 'datadog/core/environment/ext'
require 'sys/uname'

module Datadog
  module Core
    module Telemetry
      # Module defining methods for collecting metadata
      module Collector
        module_function

        def dependencies
          Gem::Specification.map do |gem|
            Telemetry::V1::Dependency.new(name: gem.name, version: gem.version.to_s, hash: gem.hash.to_s)
          end
        end

        def integrations
          integrations = Datadog.configuration.tracing.instrumented_integrations
          integrations.map do |name, integration|
            patch_result = integration.patch
            Telemetry::V1::Integration
              .new(name: name.to_s,
                   enabled: (patch_result == true),
                   version: integration.class.version ? integration.class.version.to_s : nil,
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
          Telemetry::V1::Application
            .new(
              env: ENV.fetch(Datadog::Core::Environment::Ext::ENV_ENVIRONMENT, nil),
              language_version: Datadog::Core::Environment::Ext::LANG_VERSION,
              runtime_name: Datadog::Core::Environment::Ext::RUBY_ENGINE,
              runtime_version: Datadog::Core::Environment::Ext::ENGINE_VERSION,
              service_name: ENV.fetch(Datadog::Core::Environment::Ext::ENV_SERVICE),
              service_version: ENV.fetch(Datadog::Core::Environment::Ext::ENV_VERSION, nil),
              tracer_version: Datadog::Core::Environment::Ext::TRACER_VERSION,
              language_name: Datadog::Core::Environment::Ext::LANG
            )
        end

        def host
          Telemetry::V1::Host
            .new(
              container_id: Core::Environment::Container.container_id,
              hostname: Sys::Uname.nodename,
              kernel_name: Sys::Uname.sysname,
              kernel_release: Sys::Uname.release,
              kernel_version: Sys::Uname.version
            )
        end
      end
    end
  end
end
