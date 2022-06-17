# typed: true

require 'etc'

require 'datadog/core/environment/ext'
require 'datadog/core/telemetry/utils/validation'
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
        include Datadog::Core::Configuration
        include Telemetry::Utils::Validation

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
          flatten_configuration(Datadog.configuration.to_h, configuration_variables)
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

        def flatten_configuration(hash, configurations)
          flattened_hash = flatten_hash(hash)
          flattened_hash.each do |k, v|
            configurations << Telemetry::V1::Configuration.new(name: k.to_s, value: clean_config_value(v))
          end
        end

        def flatten_hash(hash)
          if hash.respond_to?(:to_h)
            hash.to_h.each_with_object({}) do |(k, v), h|
              if v.is_a? Array
                h[k] = v unless empty?(v)
              elsif v.respond_to?(:to_h) && !v.to_h.empty?
                flatten_hash(v.to_h).map do |h_k, h_v|
                  h["#{k}.#{h_k}"] = h_v unless empty?(h_v)
                end
              else
                h[k.to_s] = v unless empty?(v)
              end
            end
          end
        end

        def clean_config_value(v)
          if valid_string?(v) || valid_bool?(v) || valid_int?(v)
            v
          elsif v.is_a? Float
            v.round
          else
            v.to_s
          end
        end

        def empty?(v)
          v.nil? || (v.is_a? Proc) || (v == {})
        end

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
          Datadog.configuration.env
        end

        def service_name
          Datadog.configuration.service
        end

        def service_version
          Datadog.configuration.version
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
