# typed: true

require 'etc'

require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/core/environment/ext'
require 'datadog/core/environment/platform'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/appsec'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/host'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/product'
require 'datadog/core/telemetry/v1/profiler'
require 'ddtrace/transport/ext'

module Datadog
  module Core
    module Telemetry
      # Module defining methods for collecting metadata for telemetry
      # rubocop:disable Metrics/ModuleLength
      module Collector
        include Datadog::Core::Configuration

        # Forms a hash of configuration key value pairs to be sent in the additional payload
        def additional_payload
          additional_payload_variables
        end

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

        # Forms a hash of standard key value pairs to be sent in the app-started event configuration
        def configurations
          configurations = {
            DD_AGENT_HOST: Datadog.configuration.agent.host,
            DD_AGENT_TRANSPORT: agent_transport,
            DD_TRACE_SAMPLE_RATE: format_configuration_value(Datadog.configuration.tracing.sampling.default_rate),
          }
          compact_hash(configurations)
        end

        # Forms a telemetry app-started dependencies object
        def dependencies
          Gem.loaded_specs.collect do |name, loaded_gem|
            Datadog::Core::Telemetry::V1::Dependency.new(
              name: name, version: loaded_gem.version.to_s, hash: loaded_gem.hash.to_s
            )
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
            Telemetry::V1::Integration.new(
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

        TARGET_OPTIONS = [
          'ci.enabled'.freeze,
          'logger.level'.freeze,
          'profiling.advanced.code_provenance_enabled'.freeze,
          'profiling.advanced.endpoint.collection.enabled'.freeze,
          'profiling.enabled'.freeze,
          'runtime_metrics.enabled'.freeze,
          'tracing.analytics.enabled'.freeze,
          'tracing.distributed_tracing.propagation_inject_style'.freeze,
          'tracing.distributed_tracing.propogation_extract_style'.freeze,
          'tracing.enabled'.freeze,
          'tracing.log_injection'.freeze,
          'tracing.partial_flush.enabled'.freeze,
          'tracing.partial_flush.min_spans_threshold'.freeze,
          'tracing.priority_sampling'.freeze,
          'tracing.report_hostname'.freeze,
          'tracing.sampling.default_rate'.freeze,
          'tracing.sampling.rate_limit'.freeze
        ].freeze

        def additional_payload_variables
          # Whitelist of configuration options to send in additional payload object
          config_options = Datadog.configuration.to_hash
          config_options_to_keep = {}
          TARGET_OPTIONS.each do |option|
            config_options_to_keep[option] = format_configuration_value(config_options[option])
          end

          # Add some more custom additional payload values here
          config_options_to_keep['tracing.auto_instrument.enabled'.freeze] = !defined?(Datadog::AutoInstrument::LOADED).nil?
          config_options_to_keep['tracing.writer_options.buffer_size'.freeze] =
            format_configuration_value(Datadog.configuration.tracing.writer_options[:buffer_size])
          config_options_to_keep['tracing.writer_options.flush_interval'.freeze] =
            format_configuration_value(Datadog.configuration.tracing.writer_options[:flush_interval])
          config_options_to_keep['logger.instance'.freeze] = Datadog.configuration.logger.instance.class.to_s

          compact_hash(config_options_to_keep)
        end

        def format_configuration_value(value)
          # TODO: If the telemetry spec is updated to accept floats, this condition should be removed
          if value.is_a?(Float) || value.is_a?(Array)
            value.to_s
          else
            value
          end
        end

        def compact_hash(hash)
          hash.delete_if { |_k, v| v.nil? }
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

        def agent_transport
          adapter = Core::Configuration::AgentSettingsResolver.call(Datadog.configuration).adapter
          if adapter == Datadog::Transport::Ext::UnixSocket::ADAPTER
            'UDS'
          else
            'TCP'
          end
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
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
