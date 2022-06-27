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
          Telemetry::V1::Application.new(
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

        # Forms a telemetry app-started configurations object
        def configurations
          configuration_variables
        end

        # Forms telemetry app-started additional payload object
        def additional_payload
          configurations = []
          flatten_configuration(Datadog.configuration, configurations)
          configurations
        end

        # Forms a telemetry app-started dependencies object
        def dependencies
          if bundled_environment?
            Gem::Specification.map do |gem|
              Telemetry::V1::Dependency.new(name: gem.name, version: gem.version.to_s, hash: gem.hash.to_s)
            end
          end
        end

        # Forms a telemetry host object
        def host
          Telemetry::V1::Host.new(
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
                error: (patch_error(integration) if is_instrumented && !is_enabled),
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

        def bundled_environment?
          begin
            !Bundler.bundle_path.nil?
          rescue Bundler::GemfileNotFound
            false
          end
        end

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
            Telemetry::V1::Configuration.new(
              name: 'DD_AGENT_HOST', value: Datadog.configuration.agent.host || ENV.fetch('DD_AGENT_HOST', '127.0.0.1')
            ),
            Telemetry::V1::Configuration.new(name: 'DD_AGENT_TRANSPORT', value: agent_transport),
            Telemetry::V1::Configuration.new(name: 'DD_TRACE_AGENT_URL', value: environment_collector.agent_url),
            Telemetry::V1::Configuration.new(
              name: 'DD_TRACE_SAMPLE_RATE',
              value: environment_collector.sample_rate || Datadog.configuration.tracing.sampling.default_rate
            )
          ].each do |configuration|
            configurations << configuration unless configuration.value.nil?
          end
          configurations
        end

        def agent_transport
          if !!ENV.fetch('DD_APM_RECEIVER_SOCKET', nil)
            'UDS'
          else
            'TCP'
          end
        end

        def flatten_configuration(hash, configuration_array)
          flattened_hash = flatten_hash(hash)
          flattened_hash.each do |k, v|
            configuration_array << Telemetry::V1::Configuration.new(name: k.to_s, value: v)
          end
        end

        def flatten_hash(hash)
          hash.to_h.each_with_object({}) do |(k, v), h|
            if empty?(v) || (v.is_a? Array) || (v.is_a? String) || (v.is_a? Integer) || (v.is_a? Float)
              next
            elsif v.respond_to?(:to_h) && !v.to_h.empty?
              flatten_hash(v.to_h).map do |h_k, h_v|
                h["#{k}.#{h_k}"] = h_v unless empty?(h_v)
              end
            else
              h[k.to_s] = v
            end
          end
        end

        def empty?(v)
          v.nil? || (v.is_a? Proc) || (v == {})
        end

        def instrumented_integrations
          Datadog.configuration.tracing.instrumented_integrations
        end

        def instrumented?(integration)
          instrumented_integrations.include?(integration.name)
        end

        def patched?(integration)
          !!integration.klass.patcher.patch_successful
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

        def patch_error(integration)
          patch_error_result = integration.klass.patcher.patch_error_result
          if patch_error_result.nil? # if no error occurred during patching, but integration is still not instrumented
            desc = "Available?: #{integration.klass.class.available?}"
            desc += ", Loaded? #{integration.klass.class.loaded?}"
            desc += ", Compatible? #{integration.klass.class.compatible?}"
            desc += ", Patchable? #{integration.klass.class.patchable?}"
            desc
          else
            patch_error_result.to_s
          end
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
