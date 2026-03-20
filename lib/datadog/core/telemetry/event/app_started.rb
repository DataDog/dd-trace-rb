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

          def configuration(settings, agent_settings)
            # Special values that are not tied to a configuration option
            list = [
              conf_value(
                'DD_GIT_REPOSITORY_URL',
                Core::Environment::Git.git_repository_url,
                (Core::Environment::Git.git_repository_url ? Configuration::Option::Precedence::ENVIRONMENT : Configuration::Option::Precedence::DEFAULT)
              ),
              conf_value(
                'DD_GIT_COMMIT_SHA',
                Core::Environment::Git.git_commit_sha,
                (Core::Environment::Git.git_commit_sha ? Configuration::Option::Precedence::ENVIRONMENT : Configuration::Option::Precedence::DEFAULT)
              ),

              # Mix of env var, programmatic and default config, so we use unknown
              conf_value('DD_AGENT_TRANSPORT', agent_transport(agent_settings), Configuration::Option::Precedence::UNKNOWN), # rubocop:disable CustomCops/EnvStringValidationCop
            ]

            # Set by the customer application (eg. `require 'datadog/auto_instrument'`)
            auto_instrument_enabled = !defined?(Datadog::AutoInstrument::LOADED).nil?
            list << conf_value(
              'tracing.auto_instrument.enabled',
              auto_instrument_enabled,
              auto_instrument_enabled ? Configuration::Option::Precedence::PROGRAMMATIC : Configuration::Option::Precedence::DEFAULT
            )
            opentelemetry_enabled = !defined?(Datadog::OpenTelemetry::LOADED).nil?
            list << conf_value(
              'tracing.opentelemetry.enabled',
              opentelemetry_enabled,
              opentelemetry_enabled ? Configuration::Option::Precedence::PROGRAMMATIC : Configuration::Option::Precedence::DEFAULT
            )

            # Track ssi configurations
            instrumentation_source = if Datadog.const_defined?(:SingleStepInstrument, false) &&
                Datadog::SingleStepInstrument.const_defined?(:LOADED, false) &&
                Datadog::SingleStepInstrument::LOADED
              'ssi'
            else
              'manual'
            end

            list.push(
              conf_value(
                'instrumentation_source',
                instrumentation_source,
                (instrumentation_source == 'ssi') ? Configuration::Option::Precedence::PROGRAMMATIC : Configuration::Option::Precedence::DEFAULT
              ),
              conf_value(
                'DD_INJECT_FORCE',
                Core::Environment::VariableHelpers.env_to_bool('DD_INJECT_FORCE', false),
                (DATADOG_ENV.key?('DD_INJECT_FORCE') ? Configuration::Option::Precedence::ENVIRONMENT : Configuration::Option::Precedence::DEFAULT)
              ),
              conf_value(
                'DD_INJECTION_ENABLED',
                DATADOG_ENV['DD_INJECTION_ENABLED'] || '',
                (DATADOG_ENV.key?('DD_INJECTION_ENABLED') ? Configuration::Option::Precedence::ENVIRONMENT : Configuration::Option::Precedence::DEFAULT)
              ),
            )

            # Extract writer options as separate configuration payloads.
            get_telemetry_payload(settings, 'tracing.writer_options', format_value: false).each do |source|
              writer_options = source.fetch(:value, {})

              # Steep: **source causes the ::Datadog::Core::Telemetry::Event::telemetry_configuration Record
              # to become a Hash. We can assign it to a value and add an annotation to type it to the correct record.
              # However, overwriting `name` and `value` will cause a FalseAssertion diagnostic.
              list << {
                **source,
                name: 'tracing.writer_options.buffer_size',
                value: writer_options[:buffer_size]
              } # steep:ignore ArgumentTypeMismatch
              list << {
                **source,
                name: 'tracing.writer_options.flush_interval',
                value: writer_options[:flush_interval]
              } # steep:ignore ArgumentTypeMismatch
            end

            # OpenTelemetry configuration options (using environment variable names)
            otel_exporter_headers_sources = get_telemetry_payload(settings, 'opentelemetry.exporter.headers', format_value: false)
            otel_exporter_headers_sources.each { |source| source[:value] = source[:value]&.map { |key, value| "#{key}=#{value}" }&.join(',') }
            list.push(*otel_exporter_headers_sources)

            otel_exporter_metrics_headers_sources = get_telemetry_payload(settings, 'opentelemetry.metrics.headers', format_value: false)
            otel_exporter_metrics_headers_sources.each { |source| source[:value] = source[:value]&.map { |key, value| "#{key}=#{value}" }&.join(',') }
            list.push(*otel_exporter_metrics_headers_sources)

            # Add some more custom additional payload values here
            if settings.logger.instance
              logger_instance_sources = get_telemetry_payload(settings, 'logger.instance', format_value: false)
              logger_instance_sources.each { |source| source[:value] = source[:value].class.to_s unless source[:value].nil? }
              list.push(*logger_instance_sources)
            end

            # Configuration options (regular + integration specific)
            collect_all_configuration_options(settings).each do |option|
              list.push(*option.telemetry_payload)
            end

            # We still want to report nil default and programmatic values as they are valid values
            list.reject! { |entry| entry[:origin] != 'default' && entry[:origin] != 'code' && entry[:value].nil? }
            list
          end

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
          def conf_value(name, value, precedence)
            # @type var result: Configuration::Option::telemetry_configuration
            result = {
              name: name,
              value: value,
              origin: precedence.origin,
              seq_id: precedence.numeric.next,
            }
            if precedence.origin == 'fleet_stable_config'
              fleet_id = Core::Configuration::StableConfig.configuration.dig(:fleet, :id)
              result[:config_id] = fleet_id if fleet_id
            elsif precedence.origin == 'local_stable_config'
              local_id = Core::Configuration::StableConfig.configuration.dig(:local, :id)
              result[:config_id] = local_id if local_id
            end
            result
          end

          def install_signature(settings)
            {
              install_id: settings.dig('telemetry', 'install_id'),
              install_type: settings.dig('telemetry', 'install_type'),
              install_time: settings.dig('telemetry', 'install_time'),
            }
          end

          def collect_all_configuration_options(settings)
            collect_configuration_options_from(settings).concat(collect_integration_configuration_options(settings.tracing))
          end

          def collect_integration_configuration_options(tracing_settings)
            return [] unless tracing_settings.respond_to?(:instrumented_integrations)

            tracing_settings.instrumented_integrations.each_value.with_object([]) do |integration, entries|
              integration.configurations.each_value do |configuration|
                entries.concat(collect_configuration_options_from(configuration))
              end
            end
          end

          def collect_configuration_options_from(settings)
            settings.class.options.each_key.with_object([]) do |name, options|
              option = settings.send(:resolve_option, name)
              next if option.definition.skip_telemetry

              if option.is_settings?
                options.concat(collect_configuration_options_from(option.get))
              else
                options << option
              end
            end
          end

          def get_telemetry_payload(settings, config_path, format_value: true)
            split_option = config_path.split('.')
            option_name = split_option.pop
            return [] if option_name.nil?

            parent_setting = settings.dig(*split_option)
            option = parent_setting.send(:resolve_option, option_name.to_sym)
            option.telemetry_payload(format_value: format_value)
          end
        end
      end
    end
  end
end
