# frozen_string_literal: true

require_relative 'base'

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry class for the 'app-started' event
        class AppStarted < Base
          def type
            'app-started'
          end

          def payload
            {
              products: products,
              configuration: configuration,
              install_signature: install_signature,
              # DEV: Not implemented yet
              # error: error, # Start-up errors
            }
          end

          private

          def products
            # @type var products: Hash[Symbol, Hash[Symbol, Object]]
            products = {
              appsec: {
                enabled: Datadog::AppSec.enabled?,
              },
              profiler: {
                enabled: Datadog::Profiling.enabled?,
              },
              dynamic_instrumentation: {
                enabled: defined?(Datadog::DI) && Datadog::DI.respond_to?(:enabled?) && Datadog::DI.enabled?,
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
          ].freeze

          # standard:disable Metrics/AbcSize
          # standard:disable Metrics/MethodLength
          def configuration
            config = Datadog.configuration
            seq_id = Event.configuration_sequence.next

            list = [
              conf_value('DD_GIT_REPOSITORY_URL', Core::Environment::Git.git_repository_url, seq_id, 'env_var'),
              conf_value('DD_GIT_COMMIT_SHA', Core::Environment::Git.git_commit_sha, seq_id, 'env_var'),

              conf_value('DD_AGENT_HOST', config.agent.host, seq_id),
              conf_value('DD_AGENT_TRANSPORT', agent_transport(config), seq_id),
              conf_value('DD_TRACE_SAMPLE_RATE', to_value(config.tracing.sampling.default_rate), seq_id),
              conf_value(
                'DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED',
                config.tracing.contrib.global_default_service_name.enabled,
                seq_id
              ),
              conf_value(
                'DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED',
                config.tracing.contrib.peer_service_defaults,
                seq_id
              ),
            ]

            peer_service_mapping_str = ''
            unless config.tracing.contrib.peer_service_mapping.empty?
              peer_service_mapping = config.tracing.contrib.peer_service_mapping
              peer_service_mapping_str = peer_service_mapping.map { |key, value| "#{key}:#{value}" }.join(',')
            end
            list << conf_value('DD_TRACE_PEER_SERVICE_MAPPING', peer_service_mapping_str, seq_id)

            # Whitelist of configuration options to send in additional payload object
            TARGET_OPTIONS.each do |option|
              split_option = option.split('.')
              list << conf_value(option, to_value(config.dig(*split_option)), seq_id)
            end

            instrumentation_source = defined?(Datadog::SingleStepInstrument::LOADED) ? 'ssi' : 'manual'
            inject_force = Core::Environment::VariableHelpers.env_to_bool('DD_INJECT_FORCE', false)
            # Track ssi configurations
            list.push(
              conf_value('instrumentation_source', instrumentation_source, seq_id),
              conf_value('DD_INJECT_FORCE', inject_force , seq_id),
              conf_value('DD_INJECTION_ENABLED', ENV['DD_INJECTION_ENABLED'] || '', seq_id),
            )

            # Add some more custom additional payload values here
            list.push(
              conf_value('tracing.auto_instrument.enabled', !defined?(Datadog::AutoInstrument::LOADED).nil?, seq_id),
              conf_value(
                'tracing.writer_options.buffer_size',
                to_value(config.tracing.writer_options[:buffer_size]),
                seq_id
              ),
              conf_value(
                'tracing.writer_options.flush_interval',
                to_value(config.tracing.writer_options[:flush_interval]),
                seq_id
              ),
              conf_value(
                'tracing.opentelemetry.enabled',
                !defined?(Datadog::OpenTelemetry::LOADED).nil?,
                seq_id
              ),
            )
            list << conf_value('logger.instance', config.logger.instance.class.to_s, seq_id) if config.logger.instance
            if config.respond_to?('appsec')
              list << conf_value('appsec.enabled', config.dig('appsec', 'enabled'), seq_id)
              list << conf_value('appsec.sca_enabled', config.dig('appsec', 'sca_enabled'), seq_id)
            end
            list << conf_value('ci.enabled', config.dig('ci', 'enabled'), seq_id) if config.respond_to?('ci')

            list.reject! { |entry| entry[:value].nil? }
            list
          end
          # standard:enable Metrics/AbcSize
          # standard:enable Metrics/MethodLength

          def agent_transport(config)
            adapter = Core::Configuration::AgentSettingsResolver.call(config).adapter
            if adapter == Datadog::Core::Transport::Ext::UnixSocket::ADAPTER
              'UDS'
            else
              'TCP'
            end
          end

          def conf_value(name, value, seq_id, origin = 'code')
            {
              name: name,
              value: value,
              origin: origin,
              seq_id: seq_id,
            }
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

          def install_signature
            config = Datadog.configuration
            {
              install_id: config.dig('telemetry', 'install_id'),
              install_type: config.dig('telemetry', 'install_type'),
              install_time: config.dig('telemetry', 'install_time'),
            }
          end
        end
      end
    end
  end
end
