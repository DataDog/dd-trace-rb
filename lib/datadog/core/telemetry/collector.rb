# typed: true

require 'etc'

require 'datadog/core/environment/ext'
require 'datadog/core/telemetry/v1/app_started'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/host'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/profiler'
require 'datadog/core/telemetry/v1/telemetry_request'

module Datadog
  module Core
    module Telemetry
      # Module defining methods for collecting metadata for telemetry
      # rubocop:disable Metrics/ModuleLength
      module Collector
        def application
          Telemetry::V1::Application
            .new(
              env: env,
              language_name: Datadog::Core::Environment::Ext::LANG,
              language_version: Datadog::Core::Environment::Ext::LANG_VERSION,
              products: products,
              runtime_name: Datadog::Core::Environment::Ext::RUBY_ENGINE,
              runtime_version: Datadog::Core::Environment::Ext::ENGINE_VERSION,
              service_name: service_name,
              service_version: service_version,
              tracer_version: Datadog::Core::Environment::Ext::TRACER_VERSION
            )
        end

        def configurations
          configuration_variables = []
          ENV.each do |key, value|
            if configuration_variable?(key, value)
              configuration_variables << Telemetry::V1::Configuration.new(name: key, value: value)
            end
          end
          configuration_variables
        end

        def dependencies
          Gem::Specification.map do |gem|
            Telemetry::V1::Dependency.new(name: gem.name, version: gem.version.to_s, hash: gem.hash.to_s)
          end
        end

        def host
          Telemetry::V1::Host
            .new(
              container_id: Core::Environment::Container.container_id,
              hostname: hostname,
              kernel_name: kernel_name,
              kernel_release: kernel_release,
              kernel_version: kernel_version
            )
        end

        def integrations
          Datadog.registry.map do |integration|
            is_instrumented = instrumented?(integration)
            is_enabled = is_instrumented && patched?(integration)
            Telemetry::V1::Integration
              .new(
                name: integration.name.to_s,
                enabled: is_enabled,
                version: integration_version(integration),
                compatible: integration_compatible?(integration),
                error: (integration_error(integration) if is_instrumented && !is_enabled),
                auto_enabled: is_enabled ? integration_auto_instrument?(integration) : nil
              )
          end
        end

        def runtime_id
          Datadog::Core::Environment::Identity.id
        end

        def tracer_time
          Time.now.to_i
        end

        private

        def products
          profiler_obj = profiler
          appsec_obj = appsec
          profiler_obj || appsec_obj ? Telemetry::V1::Product.new(profiler: profiler_obj, appsec: appsec_obj) : nil
        end

        def integration_auto_instrument?(integration)
          integration.klass.auto_instrument?
        end

        def integration_compatible?(integration)
          integration.klass.class.compatible?
        end

        def instrumented?(integration)
          instrumented_integrations.include?(integration.name)
        end

        def instrumented_integrations
          Datadog.configuration.tracing.instrumented_integrations
        end

        def patched?(integration)
          instrumented_integrations[integration.name].patch == true
        end

        def integration_version(integration)
          integration.klass.class.version ? integration.klass.class.version.to_s : nil
        end

        def patch_result(integration)
          instrumented_integrations[integration.name].patch
        end

        def hostname
          Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' ? Etc.uname[:nodename] : nil
        end

        def kernel_name
          Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' ? Etc.uname[:sysname] : Gem::Platform.local.os.capitalize
        end

        def kernel_release
          Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' ? Etc.uname[:release] : nil
        end

        def kernel_version
          Datadog::Core::Environment::Ext::LANG_VERSION >= '2.2' ? Etc.uname[:version] : nil
        end

        def configuration_variable?(key, value)
          key.to_s.start_with?('DD') && !value.empty?
        end

        def profiler_version
          if Datadog.configuration.respond_to?(:profiling) && Datadog.configuration.profiling.enabled
            Core::Environment::Identity.tracer_version
          end
        end

        def appsec_version
          if Datadog.configuration.respond_to?(:appsec) && Datadog.configuration.appsec.enabled
            Core::Environment::Identity.tracer_version
          end
        end

        def profiler
          version = profiler_version
          Telemetry::V1::Profiler.new(version: version) if version
        end

        def appsec
          version = appsec_version
          Telemetry::V1::AppSec.new(version: version) if version
        end

        def env
          ENV.fetch(Datadog::Core::Environment::Ext::ENV_ENVIRONMENT, nil)
        end

        def service_name
          ENV.fetch(Datadog::Core::Environment::Ext::ENV_SERVICE)
        end

        def service_version
          ENV.fetch(Datadog::Core::Environment::Ext::ENV_VERSION, nil)
        end

        def integration_error(integration)
          patch_result = patch_result(integration)
          desc = "Available?: #{patch_result[:available]}"
          desc += ", Loaded? #{patch_result[:loaded]}"
          desc += ", Compatible? #{patch_result[:compatible]}"
          desc += ", Patchable? #{patch_result[:patchable]}"
          desc
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
