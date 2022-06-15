# typed: true

require 'datadog/core/environment/ext'
require 'datadog/core/telemetry/v1/app_started'
require 'datadog/core/telemetry/v1/application'
require 'datadog/core/telemetry/v1/dependency'
require 'datadog/core/telemetry/v1/host'
require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/profiler'
require 'datadog/core/telemetry/v1/telemetry_request'
require 'etc'

module Datadog
  module Core
    module Telemetry
      # Module defining methods for collecting metadata
      # rubocop:disable Metrics/ModuleLength
      module Collector
        API_VERSION = 'v1'.freeze
        @seq_id = 1

        module_function

        def request(request_type, api_version = Collector::API_VERSION)
          case request_type
          when 'app-started'
            payload = app_started
            telemetry_request(request_type, api_version, payload)
          else
            raise ArgumentError, "Request type invalid, received request_type: #{request_type}"
          end
        end

        private_class_method def self.telemetry_request(request_type, api_version, payload)
          request = Telemetry::V1::TelemetryRequest.new(
            api_version: api_version,
            application: application,
            host: host,
            payload: payload,
            request_type: request_type,
            runtime_id: Datadog::Core::Environment::Identity.id,
            seq_id: @seq_id,
            tracer_time: Time.now.to_i,
          )
          @seq_id += 1
          request
        end

        private_class_method def self.app_started
          Telemetry::V1::AppStarted.new(
            dependencies: dependencies,
            integrations: integrations,
            configuration: configuration
          )
        end

        private_class_method def self.dependencies
          Gem::Specification.map do |gem|
            Telemetry::V1::Dependency.new(name: gem.name, version: gem.version.to_s, hash: gem.hash.to_s)
          end
        end

        private_class_method def self.integration_error(patch_result)
          desc = "Available?: #{patch_result[:available]}"
          desc += ", Loaded? #{patch_result[:loaded]}"
          desc += ", Compatible? #{patch_result[:compatible]}"
          desc += ", Patchable? #{patch_result[:patchable]}"
          desc
        end

        private_class_method def self.integrations
          registry = Datadog.registry
          instrumented_integrations = Datadog.configuration.tracing.instrumented_integrations
          registry.map do |integration|
            is_instrumented = instrumented_integrations.include?(integration.name)
            is_enabled = is_instrumented && instrumented_integrations[integration.name].patch == true
            Telemetry::V1::Integration
              .new(name: integration.name.to_s,
                   enabled: is_enabled,
                   version: integration.klass.class.version ? integration.klass.class.version.to_s : nil,
                   compatible: integration.klass.class.compatible?,
                   error: if is_instrumented && !is_enabled
                            integration_error(instrumented_integrations[integration.name].patch)
                          end,
                   auto_enabled: is_enabled ? integration.klass.auto_instrument? : nil) # is this the right value?
          end
        end

        private_class_method def self.application
          Telemetry::V1::Application
            .new(
              env: ENV.fetch(Datadog::Core::Environment::Ext::ENV_ENVIRONMENT, nil),
              language_version: Datadog::Core::Environment::Ext::LANG_VERSION,
              runtime_name: Datadog::Core::Environment::Ext::RUBY_ENGINE,
              runtime_version: Datadog::Core::Environment::Ext::ENGINE_VERSION,
              service_name: ENV.fetch(Datadog::Core::Environment::Ext::ENV_SERVICE),
              service_version: ENV.fetch(Datadog::Core::Environment::Ext::ENV_VERSION, nil),
              tracer_version: Datadog::Core::Environment::Ext::TRACER_VERSION,
              language_name: Datadog::Core::Environment::Ext::LANG,
              products: products
            )
        end

        private_class_method def self.host
          # Etc.uname is only available in stdlib from Ruby v2.2 onwards
          if Datadog::Core::Environment::Ext::LANG_VERSION < '2.2'
            Telemetry::V1::Host.new(container_id: Core::Environment::Container.container_id)
          else
            Telemetry::V1::Host
              .new(
                container_id: Core::Environment::Container.container_id,
                hostname: Etc.uname[:nodename],
                kernel_name: Etc.uname[:sysname],
                kernel_release: Etc.uname[:release],
                kernel_version: Etc.uname[:version]
              )
          end
        end

        private_class_method def self.configuration
          configurations = []
          ENV.each do |key, value|
            next unless key.to_s.include?('DD') && !value.empty?

            configurations << Telemetry::V1::Configuration.new(name: key, value: value)
          end
          configurations
        end

        private_class_method def self.products
          Telemetry::V1::Product.new(profiler: profiling, appsec: appsec)
        end

        private_class_method def self.profiling
          if Datadog.configuration.respond_to?(:profiling)
            Telemetry::V1::Profiler.new(version: Core::Environment::Identity.tracer_version)
          end
        end

        private_class_method def self.appsec
          if Datadog.configuration.respond_to?(:appsec)
            Telemetry::V1::AppSec.new(version: Core::Environment::Identity.tracer_version)
          end
        end
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
