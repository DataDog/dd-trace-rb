# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      class Event
        # Base class for all Telemetry V2 events.
        class Base
          # The type of the event.
          # It must be one of the stings defined in the Telemetry V2
          # specification for event names.
          def type; end

          # The JSON payload for the event.
          # @param seq_id [Integer] The sequence ID for the event.
          def payload(seq_id)
            {}
          end
        end

        # Telemetry class for the 'app-started' event
        class AppStarted < Base
          def type
            'app-started'
          end

          def payload(seq_id)
            @seq_id = seq_id
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
            tracing.distributed_tracing.propagation_inject_style
            tracing.distributed_tracing.propagation_extract_style
            tracing.enabled
            tracing.log_injection
            tracing.partial_flush.enabled
            tracing.partial_flush.min_spans_threshold
            tracing.report_hostname
            tracing.sampling.rate_limit
          ].freeze

          # rubocop:disable Metrics/AbcSize
          def configuration
            config = Datadog.configuration

            list = [
              conf_value('DD_AGENT_HOST', config.agent.host),
              conf_value('DD_AGENT_TRANSPORT', agent_transport(config)),
              conf_value('DD_TRACE_SAMPLE_RATE', to_value(config.tracing.sampling.default_rate)),
              conf_value(
                'DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED',
                config.tracing.contrib.global_default_service_name.enabled
              ),
            ]

            peer_service_mapping_str = ''
            unless config.tracing.contrib.peer_service_mapping.empty?
              peer_service_mapping = config.tracing.contrib.peer_service_mapping
              peer_service_mapping_str = peer_service_mapping.map { |key, value| "#{key}:#{value}" }.join(',')
            end
            list << conf_value('DD_TRACE_PEER_SERVICE_MAPPING', peer_service_mapping_str)

            # Whitelist of configuration options to send in additional payload object
            TARGET_OPTIONS.each do |option|
              split_option = option.split('.')
              list << conf_value(option, to_value(config.dig(*split_option)))
            end

            # Add some more custom additional payload values here
            list.push(
              conf_value('tracing.auto_instrument.enabled', !defined?(Datadog::AutoInstrument::LOADED).nil?),
              conf_value('tracing.writer_options.buffer_size', to_value(config.tracing.writer_options[:buffer_size])),
              conf_value('tracing.writer_options.flush_interval', to_value(config.tracing.writer_options[:flush_interval])),
              conf_value('tracing.opentelemetry.enabled', !defined?(Datadog::OpenTelemetry::LOADED).nil?),
            )
            list << conf_value('logger.instance', config.logger.instance.class.to_s) if config.logger.instance
            list << conf_value('appsec.enabled', config.dig('appsec', 'enabled')) if config.respond_to?('appsec')
            list << conf_value('ci.enabled', config.dig('ci', 'enabled')) if config.respond_to?('ci')

            list.reject! { |entry| entry[:value].nil? }
            list
          end
          # rubocop:enable Metrics/AbcSize

          def agent_transport(config)
            adapter = Core::Configuration::AgentSettingsResolver.call(config).adapter
            if adapter == Datadog::Core::Transport::Ext::UnixSocket::ADAPTER
              'UDS'
            else
              'TCP'
            end
          end

          def conf_value(name, value, origin = 'code')
            {
              name: name,
              value: value,
              origin: origin,
              seq_id: @seq_id,
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

          def payload(seq_id)
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

          def payload(seq_id)
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

          def payload(seq_id)
            {
              configuration: @changes.map do |name, value|
                {
                  name: name,
                  value: value,
                  origin: @origin,
                }
              end
            }
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
      end
    end
  end
end
