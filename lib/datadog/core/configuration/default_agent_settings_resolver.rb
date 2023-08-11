# frozen_string_literal: true

require 'uri'

require_relative 'settings'
require_relative '../../../ddtrace/transport/ext'
require_relative 'agent_settings_resolver'

module Datadog
  module Core
    module Configuration
      # TODO: EK - UPDATE COMMENT

      # This class unifies all the different ways that users can configure how we talk to the agent.
      #
      # It has quite a lot of complexity, but this complexity just reflects the actual complexity we have around our
      # configuration today. E.g., this is just all of the complexity regarding agent settings gathered together in a
      # single place. As we deprecate more and more of the different ways that these things can be configured,
      # this class will reflect that simplification as well.
      #
      # Whenever there is a conflict (different configurations are provided in different orders), it MUST warn the users
      # about it and pick a value based on the following priority: code > environment variable > defaults.
      class DefaultAgentSettingsResolver
        include AgentSettingsResolver

        AgentSettings = Class.new(BaseAgentSettings) do
          # TODO: IMPLEMENT
        end

        def self.call(settings, logger: Datadog.logger)
          new(settings, logger: logger).send(:call)
        end

        private

        attr_reader \
          :logger,
          :settings

        def initialize(settings, logger: Datadog.logger)
          @settings = settings
          @logger = logger
        end

        def call
          AgentSettings.new(
            adapter: adapter,
            ssl: ssl?,
            hostname: hostname,
            port: port,
            uds_path: uds_path,
            timeout_seconds: timeout_seconds,
            # NOTE: When provided, the deprecated_for_removal_transport_configuration_proc can override all
            # values above (ssl, hostname, port, timeout), or even make them irrelevant (by using an unix socket or
            # enabling test mode instead).
            # That is the main reason why it is deprecated -- it's an opaque function that may set a bunch of settings
            # that we know nothing of until we actually call it.
            # deprecated_for_removal_transport_configuration_proc: deprecated_for_removal_transport_configuration_proc,
          )
        end

        def adapter
          if should_use_uds? && !mixed_http_and_uds?
            Datadog::Transport::Ext::UnixSocket::ADAPTER
          else
            Datadog::Transport::Ext::HTTP::ADAPTER
          end
        end

        def configured_hostname
          return @configured_hostname if defined?(@configured_hostname)

          @configured_hostname = pick_from(
            DetectedConfiguration.new(
              friendly_name: "'c.agent.host'",
              value: settings.agent.host
            ),
            DetectedConfiguration.new(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_HOST} environment variable",
              value: ENV[Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_HOST]
            )
          )
        end

        def configured_port
          return @configured_port if defined?(@configured_port)

          @configured_port = pick_from(
            try_parsing_as_integer(
              friendly_name: '"c.agent.port"',
              value: settings.agent.port,
            ),
            try_parsing_as_integer(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_PORT} environment variable",
              value: ENV[Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_PORT],
            )
          )
        end

        def ssl?
          false
        end

        def hostname
          configured_hostname || (should_use_uds? ? nil : Datadog::Transport::Ext::HTTP::DEFAULT_HOST)
        end

        def port
          configured_port || (should_use_uds? ? nil : Datadog::Transport::Ext::HTTP::DEFAULT_PORT)
        end

        # Unix socket path in the file system
        def uds_path
          if mixed_http_and_uds?
            nil
          else
            uds_fallback
          end
        end

        # Defaults to +nil+, letting the adapter choose what default
        # works best in their case.
        def timeout_seconds
          nil
        end

        # In transport_options, we try to invoke the transport_options proc and get its configuration. In case that
        # doesn't work, we include the proc directly in the agent settings result.
        def deprecated_for_removal_transport_configuration_proc
          nil
        end

        # We only use the default unix socket if it is already present.
        # This is by design, as we still want to use the default host:port if no unix socket is present.
        def uds_fallback
          return @uds_fallback if defined?(@uds_fallback)

          @uds_fallback =
            if configured_hostname.nil? &&
                configured_port.nil? &&
                File.exist?(Datadog::Transport::Ext::UnixSocket::DEFAULT_PATH)

              Datadog::Transport::Ext::UnixSocket::DEFAULT_PATH
            end
        end

        def should_use_uds?
          # If no agent settings have been provided, we try to connect using a local unix socket.
          # We only do so if the socket is present when `ddtrace` runs.
          !uds_fallback.nil?
        end

        def pick_from(*configurations_in_priority_order)
          detected_configurations_in_priority_order = configurations_in_priority_order.select(&:value?)

          if detected_configurations_in_priority_order.any?
            warn_if_configuration_mismatch(detected_configurations_in_priority_order)

            # The configurations are listed in priority, so we only need to look at the first; if there's more than
            # one, we emit a warning above
            detected_configurations_in_priority_order.first.value
          end
        end

        def warn_if_configuration_mismatch(detected_configurations_in_priority_order)
          return unless detected_configurations_in_priority_order.map(&:value).uniq.size > 1

          log_warning(
            'Configuration mismatch: values differ between ' \
            "#{detected_configurations_in_priority_order
              .map { |config| "#{config.friendly_name} (#{config.value.inspect})" }.join(' and ')}" \
            ". Using #{detected_configurations_in_priority_order.first.value.inspect}."
          )
        end

        # Expected to return nil (not false!) when it's not http
        def parsed_http_url
          nil
        end

        # When we have mixed settings for http/https and uds, we print a warning and ignore the uds settings
        def mixed_http_and_uds?
          return @mixed_http_and_uds if defined?(@mixed_http_and_uds)

          @mixed_http_and_uds = (configured_hostname || configured_port) && should_use_uds?

          if @mixed_http_and_uds
            warn_if_configuration_mismatch(
              [
                DetectedConfiguration.new(
                  friendly_name: 'configuration of hostname/port for http/https use',
                  value: "hostname: '#{configured_hostname}', port: #{configured_port.inspect}",
                ),
                DetectedConfiguration.new(
                  friendly_name: 'configuration for unix domain socket',
                  value: "unix://#{uds_path}",
                ),
              ]
            )
          end

          @mixed_http_and_uds
        end
      end
    end
  end
end
