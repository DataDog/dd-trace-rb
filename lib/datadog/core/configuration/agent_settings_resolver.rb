# frozen_string_literal: true

require 'uri'

require_relative 'settings'
require_relative '../../../ddtrace/transport/ext'
require_relative 'agent_settings_resolver_common'

module Datadog
  module Core
    module Configuration
      # This class unifies different ways that users can configure how we talk to the agent that are not specific to
      # individual components. Components like Tracing and Profiling have their own resolvers that implement
      # component specific functionality. This resolver should not depend on any components outside of core.
      #
      # WARN: If you change any functionality here you may have to also change component specific resolvers until
      # they are deprecated and removed.
      #
      # It has quite a lot of complexity, but this complexity just reflects the actual complexity we have around our
      # configuration today. E.g., this is just all of the complexity regarding agent settings gathered together in a
      # single place. As we deprecate more and more of the different ways that these things can be configured,
      # this class will reflect that simplification as well.
      #
      # Whenever there is a conflict (different configurations are provided in different orders), it MUST warn the users
      # about it and pick a value based on the following priority: code > environment variable > defaults.
      class AgentSettingsResolver
        include AgentSettingsResolverCommon

        AgentSettings = Class.new(BaseAgentSettings)

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
          )
        end

        def configured_hostname
          return @configured_hostname if defined?(@configured_hostname)

          @configured_hostname = pick_from(
            DetectedConfiguration.new(
              friendly_name: "'c.agent.host'",
              value: settings.agent.host
            ),
            DetectedConfiguration.new(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_URL} environment variable",
              value: parsed_http_url && parsed_http_url.hostname
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
            DetectedConfiguration.new(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_URL} environment variable",
              value: parsed_http_url && parsed_http_url.port,
            ),
            try_parsing_as_integer(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_PORT} environment variable",
              value: ENV[Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_PORT],
            )
          )
        end

        def ssl?
            !parsed_url.nil? && parsed_url.scheme == 'https'
        end

        def hostname
          configured_hostname || (should_use_uds? ? nil : Datadog::Transport::Ext::HTTP::DEFAULT_HOST)
        end

        def port
          configured_port || (should_use_uds? ? nil : Datadog::Transport::Ext::HTTP::DEFAULT_PORT)
        end

        # Defaults to +nil+, letting the adapter choose what default
        # works best in their case.
        def timeout_seconds
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


        def parsed_url
          return @parsed_url if defined?(@parsed_url)

          unparsed_url_from_env = ENV[Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_URL]

          @parsed_url =
            if unparsed_url_from_env
              parsed = URI.parse(unparsed_url_from_env)

              if http_scheme?(parsed) || unix_scheme?(parsed)
                parsed
              else
                # rubocop:disable Layout/LineLength
                log_warning(
                  "Invalid URI scheme '#{parsed.scheme}' for #{Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_URL} " \
                  "environment variable ('#{unparsed_url_from_env}'). " \
                  "Ignoring the contents of #{Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_URL}."
                )
                # rubocop:enable Layout/LineLength

                nil
              end
            end
        end
      end
    end
  end
end
