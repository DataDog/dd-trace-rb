# frozen_string_literal: true

require_relative 'base'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry class for the 'app-started' event
        class AppStarted < Base
          def initialize(components:)
            # To not hold a reference to the component tree, generate
            # the event payload here in the constructor.
            #
            # Important: do not store data that contains (or is derived from)
            # the runtime_id or sequence numbers.
            # This event is reused when a process forks, but in the
            # child process the runtime_id would be different and sequence
            # number is reset.
            @configuration = configuration(components.settings, components.agent_settings)
            @install_signature = install_signature(components.settings)
            @products = products(components)
          end

          def type
            'app-started'
          end

          def payload
            {
              products: @products,
              configuration: @configuration,
              install_signature: @install_signature,
              # DEV: Not implemented yet
              # error: error, # Start-up errors
            }
          end

          # Whether the event is actually the app-started event.
          # For the app-started event we follow up by sending
          # app-dependencies-loaded, if the event is
          # app-client-configuration-change we don't send
          # app-dependencies-loaded.
          def app_started?
            true
          end

          private

          def products(components)
            # @type var products: telemetry_products
            products = {
              appsec: {
                # TODO take appsec status out of component tree?
                enabled: components.settings.appsec.enabled,
              },
              profiler: {
                enabled: !!components.profiler&.enabled?,
              },
              dynamic_instrumentation: {
                enabled: !!components.dynamic_instrumentation,
              }
            }

            if (unsupported_reason = Datadog::Profiling.unsupported_reason)
              products[:profiler][:error] = {
                code: 1, # Error code. 0 if no error.
                message: unsupported_reason,
              }
            end

            products
          end

          TARGET_OPTIONS = %w[
            dynamic_instrumentation.enabled
            logger.level
            profiling.advanced.code_provenance_enabled
            profiling.advanced.endpoint.collection.enabled
            profiling.enabled
            runtime_metrics.enabled
            tracing.analytics.enabled
            tracing.propagation_style_extract
            tracing.propagation_style_inject
            tracing.enabled
            tracing.log_injection
            tracing.partial_flush.enabled
            tracing.partial_flush.min_spans_threshold
            tracing.report_hostname
            tracing.sampling.rate_limit
            apm.tracing.enabled
            agent.host
            tracing.sampling.default_rate
            tracing.contrib.global_default_service_name.enabled
            tracing.contrib.peer_service_defaults
            tracing.contrib.peer_service_mapping
            diagnostics.debug
            opentelemetry.exporter.endpoint
            opentelemetry.exporter.protocol
            opentelemetry.exporter.timeout_millis
            opentelemetry.metrics.enabled
            opentelemetry.metrics.exporter
            opentelemetry.metrics.endpoint
            opentelemetry.metrics.protocol
            opentelemetry.metrics.timeout_millis
            opentelemetry.metrics.temporality_preference
            opentelemetry.metrics.export_interval_millis
            opentelemetry.metrics.export_timeout_millis
          ].freeze

          # standard:disable Metrics/AbcSize
          # standard:disable Metrics/MethodLength
          def configuration(settings, agent_settings)
            list = [
              # Only set using env var as of June 2025
              conf_value('DD_GIT_REPOSITORY_URL', Core::Environment::Git.git_repository_url, 3, 'env_var'),
              conf_value('DD_GIT_COMMIT_SHA', Core::Environment::Git.git_commit_sha, 3, 'env_var'),

              # Set by the customer application (eg. `require 'datadog/auto_instrument'`)
              conf_value(
                'tracing.auto_instrument.enabled',
                !defined?(Datadog::AutoInstrument::LOADED).nil?,
                5,
                'code'
              ),
              conf_value(
                'tracing.opentelemetry.enabled',
                !defined?(Datadog::OpenTelemetry::LOADED).nil?,
                5,
                'code'
              ),

              # Mix of env var, programmatic and default config, so we use unknown
              conf_value('DD_AGENT_TRANSPORT', agent_transport(agent_settings), 7, 'unknown'), # rubocop:disable CustomCops/EnvStringValidationCop
            ]

            # tracing.writer_options.buffer_size and tracing.writer_options.flush_interval have the same origin.
            writer_option_sources = get_telemetry_payload(settings, 'tracing.writer_options', stringify_value: false)
            writer_option_sources.each do |source|
              buffer_size_source = source.dup
              flush_interval_source = source
              buffer_size_source[:name] = 'tracing.writer_options.buffer_size'
              buffer_size_source[:value] = to_value(source[:value][:buffer_size])
              flush_interval_source[:name] = 'tracing.writer_options.flush_interval'
              flush_interval_source[:value] = to_value(source[:value][:flush_interval])
              list.push(buffer_size_source, flush_interval_source)
            end

            # OpenTelemetry configuration options (using environment variable names)
            otel_exporter_headers_sources = get_telemetry_payload(settings, 'opentelemetry.exporter.headers', stringify_value: false)
            otel_exporter_headers_sources.each { |source| source[:value] = source[:value]&.map { |key, value| "#{key}=#{value}" }&.join(',') }
            list.push(*otel_exporter_headers_sources)

            otel_exporter_metrics_headers_sources = get_telemetry_payload(settings, 'opentelemetry.metrics.headers', stringify_value: false)
            otel_exporter_metrics_headers_sources.each { |source| source[:value] = source[:value]&.map { |key, value| "#{key}=#{value}" }&.join(',') }
            list.push(*otel_exporter_metrics_headers_sources)

            # Whitelist of configuration options to send in additional payload object
            TARGET_OPTIONS.each do |option_path|
              list.push(*get_telemetry_payload(settings, option_path))
            end

            instrumentation_source = if Datadog.const_defined?(:SingleStepInstrument, false) &&
                Datadog::SingleStepInstrument.const_defined?(:LOADED, false) &&
                Datadog::SingleStepInstrument::LOADED
              'ssi'
            else
              'manual'
            end
            # Track ssi configurations
            list.push(
              conf_value('instrumentation_source', instrumentation_source, 5, 'code'),
              conf_value('DD_INJECT_FORCE', Core::Environment::VariableHelpers.env_to_bool('DD_INJECT_FORCE', false), 3, 'env_var'),
              conf_value('DD_INJECTION_ENABLED', DATADOG_ENV['DD_INJECTION_ENABLED'] || '', 3, 'env_var'),
            )

            # Add some more custom additional payload values here
            if settings.logger.instance
              logger_instance_sources = get_telemetry_payload(settings, 'logger.instance', stringify_value: false)
              logger_instance_sources.each { |source| source[:value] = source[:value].class.to_s }
              list.push(*logger_instance_sources)
            end
            if settings.respond_to?('appsec')
              list.push(*get_telemetry_payload(settings, 'appsec.enabled'))
              list.push(*get_telemetry_payload(settings, 'appsec.sca_enabled'))
            end
            if settings.respond_to?('ci')
              list.push(*get_telemetry_payload(settings, 'ci.enabled'))
            end

            list.reject! { |entry| entry[:value].nil? }
            list
          end
          # standard:enable Metrics/AbcSize
          # standard:enable Metrics/MethodLength

          def agent_transport(agent_settings)
            adapter = agent_settings.adapter
            if adapter == Datadog::Core::Transport::Ext::UnixSocket::ADAPTER
              'UDS'
            else
              'TCP'
            end
          end

          # `origin`: Source of the configuration. One of :
          # - 1: `default`: set when the user has not set any configuration for the key (defaults to a value)
          # - 2:`local_stable_config`: configuration set via a user-managed file
          # - 3:`env_var`: configurations that are set through environment variables
          # - 4:`fleet_stable_config`: configuration is set via the fleet automation Datadog UI
          # - 5:`code`: configurations that are set through the customer application
          # - 6:`remote_config`: values that are set using remote config
          # - 7:`unknown`: set for cases where it is difficult/not possible to determine the source of a config.
          def conf_value(name, value, seq_id, origin)
            # @type var result: telemetry_configuration
            result = {name: name, value: value, origin: origin, seq_id: seq_id}
            if origin == 'fleet_stable_config'
              fleet_id = Core::Configuration::StableConfig.configuration.dig(:fleet, :id)
              result[:config_id] = fleet_id if fleet_id
            elsif origin == 'local_stable_config'
              local_id = Core::Configuration::StableConfig.configuration.dig(:local, :id)
              result[:config_id] = local_id if local_id
            end
            result
          end

          def to_value(value)
            # TODO: Add float if telemetry starts accepting it
            case value
            when Integer, String, true, false, nil
              value
            else
              value.to_s
            end
          end

          def install_signature(settings)
            {
              install_id: settings.dig('telemetry', 'install_id'),
              install_type: settings.dig('telemetry', 'install_type'),
              install_time: settings.dig('telemetry', 'install_time'),
            }
          end

          def get_telemetry_origin(settings, config_path)
            split_option = config_path.split('.')
            option_name = split_option.pop
            return 'unknown' if option_name.nil?

            # @type var parent_setting: Core::Configuration::Options
            # @type var option: Core::Configuration::Option
            parent_setting = settings.dig(*split_option)
            option = parent_setting.send(:resolve_option, option_name.to_sym)
            option.precedence_set&.origin || 'unknown'
          end

          def get_telemetry_payload(settings, config_path, stringify_value: true)
            split_option = config_path.split('.')
            option_name = split_option.pop
            return [] if option_name.nil?

            # @type var parent_setting: Core::Configuration::Options
            # @type var option: Core::Configuration::Option
            parent_setting = settings.dig(*split_option)
            option = parent_setting.send(:resolve_option, option_name.to_sym)
            option.telemetry_payload(stringify_value: stringify_value)
          end
        end
      end
    end
  end
end
