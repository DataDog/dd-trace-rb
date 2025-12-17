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

          private

          def products(components)
            # @type var products: Hash[Symbol, Hash[Symbol, Hash[Symbol, String | Integer] | bool | nil]]
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
          ].freeze

          # standard:disable Metrics/AbcSize
          # standard:disable Metrics/MethodLength
          def configuration(settings, agent_settings)
            seq_id = Event.configuration_sequence.next

            # tracing.writer_options.buffer_size and tracing.writer_options.flush_interval have the same origin.
            writer_option_origin = get_telemetry_origin(settings, 'tracing.writer_options')

            list = [
              # Only set using env var as of June 2025
              conf_value('DD_GIT_REPOSITORY_URL', Core::Environment::Git.git_repository_url, seq_id, 'env_var'),
              conf_value('DD_GIT_COMMIT_SHA', Core::Environment::Git.git_commit_sha, seq_id, 'env_var'),

              # Set by the customer application (eg. `require 'datadog/auto_instrument'`)
              conf_value(
                'tracing.auto_instrument.enabled',
                !defined?(Datadog::AutoInstrument::LOADED).nil?,
                seq_id,
                'code'
              ),
              conf_value(
                'tracing.opentelemetry.enabled',
                !defined?(Datadog::OpenTelemetry::LOADED).nil?,
                seq_id,
                'code'
              ),

              # Mix of env var, programmatic and default config, so we use unknown
              conf_value('DD_AGENT_TRANSPORT', agent_transport(agent_settings), seq_id, 'unknown'), # rubocop:disable CustomCops/EnvStringValidationCop

              # writer_options is defined as an option that has a Hash value.
              conf_value(
                'tracing.writer_options.buffer_size',
                to_value(settings.tracing.writer_options[:buffer_size]),
                seq_id,
                writer_option_origin
              ),
              conf_value(
                'tracing.writer_options.flush_interval',
                to_value(settings.tracing.writer_options[:flush_interval]),
                seq_id,
                writer_option_origin
              ),

              conf_value('DD_AGENT_HOST', settings.agent.host, seq_id, get_telemetry_origin(settings, 'agent.host')),
              conf_value(
                'DD_TRACE_SAMPLE_RATE',
                to_value(settings.tracing.sampling.default_rate),
                seq_id,
                get_telemetry_origin(settings, 'tracing.sampling.default_rate')
              ),
              conf_value(
                'DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED',
                settings.tracing.contrib.global_default_service_name.enabled,
                seq_id,
                get_telemetry_origin(settings, 'tracing.contrib.global_default_service_name.enabled')
              ),
              conf_value(
                'DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED',
                settings.tracing.contrib.peer_service_defaults,
                seq_id,
                get_telemetry_origin(settings, 'tracing.contrib.peer_service_defaults')
              ),
              conf_value(
                'DD_TRACE_DEBUG',
                settings.diagnostics.debug,
                seq_id,
                get_telemetry_origin(settings, 'diagnostics.debug')
              )
            ]

            peer_service_mapping_str = ''
            unless settings.tracing.contrib.peer_service_mapping.empty?
              peer_service_mapping = settings.tracing.contrib.peer_service_mapping
              peer_service_mapping_str = peer_service_mapping.map { |key, value| "#{key}:#{value}" }.join(',')
            end
            list << conf_value(
              'DD_TRACE_PEER_SERVICE_MAPPING',
              peer_service_mapping_str,
              seq_id,
              get_telemetry_origin(settings, 'tracing.contrib.peer_service_mapping')
            )

            # OpenTelemetry configuration options (using environment variable names)
            list.push(
              conf_value('OTEL_EXPORTER_OTLP_ENDPOINT', settings.opentelemetry.exporter.endpoint, seq_id, get_telemetry_origin(settings, 'opentelemetry.exporter.endpoint')),
              conf_value('OTEL_EXPORTER_OTLP_HEADERS', settings.opentelemetry.exporter.headers, seq_id, get_telemetry_origin(settings, 'opentelemetry.exporter.headers')),
              conf_value('OTEL_EXPORTER_OTLP_PROTOCOL', settings.opentelemetry.exporter.protocol, seq_id, get_telemetry_origin(settings, 'opentelemetry.exporter.protocol')),
              conf_value('OTEL_EXPORTER_OTLP_TIMEOUT', settings.opentelemetry.exporter.timeout_millis, seq_id, get_telemetry_origin(settings, 'opentelemetry.exporter.timeout_millis')),
              conf_value('DD_METRICS_OTEL_ENABLED', settings.opentelemetry.metrics.enabled, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.enabled')),
              conf_value('OTEL_METRICS_EXPORTER', settings.opentelemetry.metrics.exporter, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.exporter')),
              conf_value('OTEL_EXPORTER_OTLP_METRICS_ENDPOINT', settings.opentelemetry.metrics.endpoint, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.endpoint')),
              conf_value('OTEL_EXPORTER_OTLP_METRICS_HEADERS', settings.opentelemetry.metrics.headers, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.headers')),
              conf_value('OTEL_EXPORTER_OTLP_METRICS_PROTOCOL', settings.opentelemetry.metrics.protocol, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.protocol')),
              conf_value('OTEL_EXPORTER_OTLP_METRICS_TIMEOUT', settings.opentelemetry.metrics.timeout_millis, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.timeout_millis')),
              conf_value('OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE', settings.opentelemetry.metrics.temporality_preference, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.temporality_preference')),
              conf_value('OTEL_METRIC_EXPORT_INTERVAL', settings.opentelemetry.metrics.export_interval_millis, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.export_interval_millis')),
              conf_value('OTEL_METRIC_EXPORT_TIMEOUT', settings.opentelemetry.metrics.export_timeout_millis, seq_id, get_telemetry_origin(settings, 'opentelemetry.metrics.export_timeout_millis')),
            )

            # Whitelist of configuration options to send in additional payload object
            TARGET_OPTIONS.each do |option_path|
              split_option = option_path.split('.')
              list << conf_value(
                option_path,
                to_value(settings.dig(*split_option)),
                seq_id,
                get_telemetry_origin(settings, option_path)
              )
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
              conf_value('instrumentation_source', instrumentation_source, seq_id, 'code'),
              conf_value('DD_INJECT_FORCE', Core::Environment::VariableHelpers.env_to_bool('DD_INJECT_FORCE', false), seq_id, 'env_var'),
              conf_value('DD_INJECTION_ENABLED', DATADOG_ENV['DD_INJECTION_ENABLED'] || '', seq_id, 'env_var'),
            )

            # Add some more custom additional payload values here
            if settings.logger.instance
              list << conf_value(
                'logger.instance',
                settings.logger.instance.class.to_s,
                seq_id,
                get_telemetry_origin(settings, 'logger.instance')
              )
            end
            if settings.respond_to?('appsec')
              list << conf_value(
                'appsec.enabled',
                settings.dig('appsec', 'enabled'),
                seq_id,
                get_telemetry_origin(settings, 'appsec.enabled')
              )
              list << conf_value(
                'appsec.sca_enabled',
                settings.dig('appsec', 'sca_enabled'),
                seq_id,
                get_telemetry_origin(settings, 'appsec.sca_enabled')
              )
            end
            if settings.respond_to?('ci')
              list << conf_value(
                'ci.enabled',
                settings.dig('ci', 'enabled'),
                seq_id,
                get_telemetry_origin(settings, 'ci.enabled')
              )
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
          # - `fleet_stable_config`: configuration is set via the fleet automation Datadog UI
          # - `local_stable_config`: configuration set via a user-managed file
          # - `env_var`: configurations that are set through environment variables
          # - `jvm_prop`: JVM system properties passed on the command line
          # - `code`: configurations that are set through the customer application
          # - `dd_config`: set by the dd.yaml file or json
          # - `remote_config`: values that are set using remote config
          # - `app.config`: only applies to .NET
          # - `default`: set when the user has not set any configuration for the key (defaults to a value)
          # - `unknown`: set for cases where it is difficult/not possible to determine the source of a config.
          def conf_value(name, value, seq_id, origin)
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
        end
      end
    end
  end
end
