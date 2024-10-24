# frozen_string_literal: true

require_relative '../utils/forking'
require_relative '../utils/sequence'

module Datadog
  module Core
    module Telemetry
      # Collection of telemetry events
      class Event
        extend Core::Utils::Forking

        # returns sequence that increments every time the configuration changes
        def self.configuration_sequence
          after_fork! { @sequence = Datadog::Core::Utils::Sequence.new(1) }
          @sequence ||= Datadog::Core::Utils::Sequence.new(1)
        end

        # Base class for all Telemetry V2 events.
        class Base
          # The type of the event.
          # It must be one of the stings defined in the Telemetry V2
          # specification for event names.
          def type
            raise NotImplementedError, 'Must be implemented by subclass'
          end

          # The JSON payload for the event.
          def payload
            {}
          end
        end

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
              # DEV: Not implemented yet
              # dynamic_instrumentation: {
              #   enabled: true,
              # }
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

          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/MethodLength
          def configuration
            config = Datadog.configuration
            seq_id = Event.configuration_sequence.next

            list = [
              conf_value('DD_AGENT_HOST', config.agent.host, seq_id),
              conf_value('DD_AGENT_TRANSPORT', agent_transport(config), seq_id),
              conf_value('DD_TRACE_SAMPLE_RATE', to_value(config.tracing.sampling.default_rate), seq_id),
              conf_value(
                'DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED',
                config.tracing.contrib.global_default_service_name.enabled,
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
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/MethodLength

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

        # Telemetry class for the 'app-dependencies-loaded' event
        class AppDependenciesLoaded < Base
          def type
            'app-dependencies-loaded'
          end

          def payload
            { dependencies: dependencies }
          end

          private

          def dependencies
            Gem.loaded_specs.collect do |name, gem|
              {
                name: name,
                version: gem.version.to_s,
                # hash: nil,
              }
            end
          end
        end

        # Telemetry class for the 'app-integrations-change' event
        class AppIntegrationsChange < Base
          def type
            'app-integrations-change'
          end

          def payload
            { integrations: integrations }
          end

          private

          def integrations
            instrumented_integrations = Datadog.configuration.tracing.instrumented_integrations
            Datadog.registry.map do |integration|
              is_instrumented = instrumented_integrations.include?(integration.name)

              is_enabled = is_instrumented ? !!integration.klass.patcher.patch_successful : false

              version = integration.klass.class.version ? integration.klass.class.version.to_s : nil

              res = {
                name: integration.name.to_s,
                enabled: is_enabled,
                version: version,
                compatible: integration.klass.class.compatible?,
                error: (patch_error(integration) if is_instrumented && !is_enabled),
                # TODO: Track if integration is instrumented by manual configuration or by auto instrumentation
                # auto_enabled: is_enabled && ???,
              }
              res.reject! { |_, v| v.nil? }
              res
            end
          end

          def patch_error(integration)
            patch_error_result = integration.klass.patcher.patch_error_result
            return patch_error_result.compact.to_s if patch_error_result

            # If no error occurred during patching, but integration is still not instrumented
            "Available?: #{integration.klass.class.available?}" \
            ", Loaded? #{integration.klass.class.loaded?}" \
            ", Compatible? #{integration.klass.class.compatible?}" \
            ", Patchable? #{integration.klass.class.patchable?}"
          end
        end

        # Telemetry class for the 'app-client-configuration-change' event
        class AppClientConfigurationChange < Base
          def type
            'app-client-configuration-change'
          end

          def initialize(changes, origin)
            super()
            @changes = changes
            @origin = origin
          end

          def payload
            { configuration: configuration }
          end

          def configuration
            config = Datadog.configuration
            seq_id = Event.configuration_sequence.next

            res = @changes.map do |name, value|
              {
                name: name,
                value: value,
                origin: @origin,
                seq_id: seq_id,
              }
            end

            unless config.dig('appsec', 'sca_enabled').nil?
              res << {
                name: 'appsec.sca_enabled',
                value: config.appsec.sca_enabled,
                origin: 'code',
                seq_id: seq_id,
              }
            end

            res
          end
        end

        # Telemetry class for the 'app-heartbeat' event
        class AppHeartbeat < Base
          def type
            'app-heartbeat'
          end
        end

        # Telemetry class for the 'app-closing' event
        class AppClosing < Base
          def type
            'app-closing'
          end
        end

        # Telemetry class for the 'generate-metrics' event
        class GenerateMetrics < Base
          def type
            'generate-metrics'
          end

          def initialize(namespace, metric_series)
            super()
            @namespace = namespace
            @metric_series = metric_series
          end

          def payload
            {
              namespace: @namespace,
              series: @metric_series.map(&:to_h)
            }
          end
        end

        # Telemetry class for the 'logs' event
        class Log < Base
          LEVELS = {
            error: 'ERROR',
            warn: 'WARN',
          }.freeze

          def type
            'logs'
          end

          def initialize(message:, level:, stack_trace: nil)
            super()
            @message = message
            @stack_trace = stack_trace
            @level = LEVELS.fetch(level) { |k| raise ArgumentError, "Invalid log level :#{k}" }
          end

          def payload
            {
              logs: [
                {
                  message: @message,
                  level: @level,
                  stack_trace: @stack_trace,
                }.compact
              ]
            }
          end
        end

        # Telemetry class for the 'distributions' event
        class Distributions < GenerateMetrics
          def type
            'distributions'
          end
        end

        # Telemetry class for the 'message-batch' event
        class MessageBatch
          attr_reader :events

          def type
            'message-batch'
          end

          def initialize(events)
            @events = events
          end

          def payload
            @events.map do |event|
              {
                request_type: event.type,
                payload: event.payload,
              }
            end
          end
        end
      end
    end
  end
end
