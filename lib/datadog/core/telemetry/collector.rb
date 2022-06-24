# typed: true

require 'etc'

require 'datadog/core/diagnostics/environment_logger'
require 'datadog/core/environment/ext'
require 'datadog/core/environment/platform'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/appsec'
require 'datadog/core/telemetry/v1/configuration'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/host'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/product'
require 'datadog/core/telemetry/v1/profiler'

module Datadog
  module Core
    module Telemetry
      # Module defining methods for collecting metadata for telemetry
      # rubocop:disable Metrics/ModuleLength
      module Collector
        include Datadog::Core::Configuration

        # Forms a telemetry application object
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
              tracer_version: tracer_version
            )
        end

        # Forms a telemetry configurations object
        def configurations
          configuration_variables
        end

        # Forms a telemetry app-started dependencies object
        def dependencies
          Gem::Specification.map do |gem|
            Telemetry::V1::Dependency.new(name: gem.name, version: gem.version.to_s, hash: gem.hash.to_s)
          end
        end

        # Forms a telemetry host object
        def host
          Telemetry::V1::Host
            .new(
              container_id: Core::Environment::Container.container_id,
              hostname: Core::Environment::Platform.hostname,
              kernel_name: Core::Environment::Platform.kernel_name,
              kernel_release: Core::Environment::Platform.kernel_release,
              kernel_version: Core::Environment::Platform.kernel_version
            )
        end

        # Forms a telemetry app-started integrations object
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

        # Returns the runtime ID of the current process
        def runtime_id
          Datadog::Core::Environment::Identity.id
        end

        # Returns the current as a UNIX timestamp in seconds
        def tracer_time
          Time.now.to_i
        end

        private

        def env
          Datadog.configuration.env
        end

        def service_name
          Datadog.configuration.service
        end

        def service_version
          Datadog.configuration.version
        end

        def tracer_version
          Core::Environment::Identity.tracer_version
        end

        def products
          profiler_obj = profiler
          appsec_obj = appsec
          profiler_obj || appsec_obj ? Telemetry::V1::Product.new(profiler: profiler_obj, appsec: appsec_obj) : nil
        end

        def profiler
          version = profiler_version
          Telemetry::V1::Profiler.new(version: version) if version
        end

        def profiler_version
          tracer_version if Datadog.configuration.respond_to?(:profiling) && Datadog.configuration.profiling.enabled
        end

        def appsec
          version = appsec_version
          Telemetry::V1::AppSec.new(version: version) if version
        end

        def appsec_version
          tracer_version if Datadog.configuration.respond_to?(:appsec) && Datadog.configuration.appsec.enabled
        end

        def configuration_variables
          configurations = []
          environment_collector = Core::Diagnostics::EnvironmentCollector.new
          [
            Telemetry::V1::Configuration.new(name: 'diagnostics.debug', value: environment_collector.debug),
            Telemetry::V1::Configuration.new(name: 'diagnostics.health_metrics.enabled',
                                             value: environment_collector.health_metrics_enabled),
            Telemetry::V1::Configuration.new(name: 'diagnostics.startup_logs.enabled',
                                             value: Datadog.configuration.diagnostics.startup_logs.enabled),
            Telemetry::V1::Configuration.new(name: 'profiling.advanced.endpoint.collection.enabled',
                                             value: Datadog.configuration.profiling.advanced.endpoint.collection.enabled),
            Telemetry::V1::Configuration.new(name: 'profiling.advanced.code_provenance_enabled',
                                             value: Datadog.configuration.profiling.advanced.code_provenance_enabled),
            Telemetry::V1::Configuration.new(name: 'profiling.advanced.legacy_transport_enabled',
                                             value: Datadog.configuration.profiling.advanced.legacy_transport_enabled),
            Telemetry::V1::Configuration.new(name: 'runtime_metrics.enabled',
                                             value: environment_collector.runtime_metrics_enabled),
            Telemetry::V1::Configuration.new(name: 'tracing.analytics.enabled',
                                             value: environment_collector.analytics_enabled),
            Telemetry::V1::Configuration.new(name: 'tracing.enabled', value: environment_collector.enabled),
            Telemetry::V1::Configuration.new(name: 'tracing.priority_sampling',
                                             value: environment_collector.priority_sampling_enabled),
            Telemetry::V1::Configuration.new(name: 'tracing.partial_flush.enabled',
                                             value: environment_collector.partial_flushing_enabled),
            Telemetry::V1::Configuration.new(name: 'tracing.sampler.rate', value: environment_collector.sample_rate),
            Telemetry::V1::Configuration.new(name: 'tracing.sampler.rules', value: environment_collector.sampling_rules),
            Telemetry::V1::Configuration.new(name: 'agent_url', value: environment_collector.agent_url),
            Telemetry::V1::Configuration.new(name: 'tags', value: environment_collector.tags)
          ].each do |configuration|
            configurations << configuration unless configuration.value.nil?
          end
          configurations
        end

        def instrumented_integrations
          Datadog.configuration.tracing.instrumented_integrations
        end

        def instrumented?(integration)
          instrumented_integrations.include?(integration.name)
        end

        def patched?(integration)
          patch_result(integration) == true
        end

        def integration_auto_instrument?(integration)
          integration.klass.auto_instrument?
        end

        def integration_compatible?(integration)
          integration.klass.class.compatible?
        end

        def integration_version(integration)
          integration.klass.class.version ? integration.klass.class.version.to_s : nil
        end

        def patch_result(integration)
          instrumented_integrations[integration.name].patcher.patch_results
        end

        def integration_error(integration)
          desc = "Available?: #{integration.klass.class.available?}"
          desc += ", Loaded? #{integration.klass.class.loaded?}"
          desc += ", Compatible? #{integration.klass.class.compatible?}"
          desc += ", Patchable? #{integration.klass.class.patchable?}"
          desc
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
