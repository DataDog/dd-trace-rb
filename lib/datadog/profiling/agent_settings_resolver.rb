# frozen_string_literal: true

require 'uri'

require_relative '../core/configuration/settings'
require_relative '../core/configuration/agent_settings_resolver_common'
require_relative '../tracing/configuration/ext'
require_relative '../../ddtrace/transport/ext'

module Datadog
  module Profiling
    # This class unifies all the different ways that users can configure how we talk to the agent.
    #
    # It has quite a lot of complexity, but this complexity just reflects the actual complexity we have around our
    # configuration today. E.g., this is just all of the complexity regarding agent settings gathered together in a
    # single place. As we deprecate more and more of the different ways that these things can be configured,
    # this class will reflect that simplification as well.
    #
    # Whenever there is a conflict (different configurations are provided in different orders), it MUST warn the users
    # about it and pick a value based on the following priority: code > environment variable > defaults.
    #
    # TODO: Decouple Tracing. Profiling relies on the deprecated_for_removal_transport_configuration_proc, which in turn
    # relies on code and constants in the Tracing namespace. This class is an exact copy of
    # Datadog::Tracing::Configuration::AgentSettingsResolver. When the proc is removed, this resolver may be replaced
    # with the implementation in Core.
    class AgentSettingsResolver
      include Core::Configuration::AgentSettingsResolverCommon

      AgentSettings = Class.new(BaseAgentSettings) do
        attr_accessor :deprecated_for_removal_transport_configuration_proc

        def initialize(deprecated_for_removal_transport_configuration_proc:, **args)
          @deprecated_for_removal_transport_configuration_proc = deprecated_for_removal_transport_configuration_proc
          super(**args)
        end
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
        # A transport_options proc configured for unix domain socket overrides most of the logic on this file
        if transport_options.adapter == Datadog::Transport::Ext::UnixSocket::ADAPTER
          return AgentSettings.new(
            adapter: Datadog::Transport::Ext::UnixSocket::ADAPTER,
            ssl: false,
            hostname: nil,
            port: nil,
            uds_path: transport_options.uds_path,
            timeout_seconds: timeout_seconds,
            deprecated_for_removal_transport_configuration_proc: nil,
          )
        end

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
          deprecated_for_removal_transport_configuration_proc: deprecated_for_removal_transport_configuration_proc,
        )
      end

      def configured_hostname
        return @configured_hostname if defined?(@configured_hostname)

        @configured_hostname = pick_from(
          DetectedConfiguration.new(
            friendly_name: "'c.tracing.transport_options'",
            value: transport_options.hostname,
          ),
          DetectedConfiguration.new(
            friendly_name: "'c.agent.host'",
            value: settings.agent.host
          ),
          DetectedConfiguration.new(
            friendly_name: "#{Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_URL} environment variable",
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
            friendly_name: "'c.tracing.transport_options'",
            value: transport_options.port,
          ),
          try_parsing_as_integer(
            friendly_name: '"c.agent.port"',
            value: settings.agent.port,
          ),
          DetectedConfiguration.new(
            friendly_name: "#{Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_URL} environment variable",
            value: parsed_http_url && parsed_http_url.port,
          ),
          try_parsing_as_integer(
            friendly_name: "#{Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_PORT} environment variable",
            value: ENV[Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_PORT],
          )
        )
      end

      def ssl?
        transport_options.ssl ||
          (!parsed_url.nil? && parsed_url.scheme == 'https')
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
        transport_options.timeout_seconds
      end

      # In transport_options, we try to invoke the transport_options proc and get its configuration. In case that
      # doesn't work, we include the proc directly in the agent settings result.
      def deprecated_for_removal_transport_configuration_proc
        if settings.tracing.transport_options.is_a?(Proc) && transport_options.adapter.nil?
          settings.tracing.transport_options
        end
      end

      # We only use the default unix socket if it is already present.
      # This is by design, as we still want to use the default host:port if no unix socket is present.
      def uds_fallback
        return @uds_fallback if defined?(@uds_fallback)

        @uds_fallback =
          if configured_hostname.nil? &&
              configured_port.nil? &&
              deprecated_for_removal_transport_configuration_proc.nil? &&
              File.exist?(Datadog::Transport::Ext::UnixSocket::DEFAULT_PATH)

            Datadog::Transport::Ext::UnixSocket::DEFAULT_PATH
          end
      end

      def parsed_url
        return @parsed_url if defined?(@parsed_url)

        unparsed_url_from_env = ENV[Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_URL]

        @parsed_url =
          if unparsed_url_from_env
            parsed = URI.parse(unparsed_url_from_env)

            if http_scheme?(parsed) || unix_scheme?(parsed)
              parsed
            else
              # rubocop:disable Layout/LineLength
              log_warning(
                "Invalid URI scheme '#{parsed.scheme}' for #{Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_URL} " \
                "environment variable ('#{unparsed_url_from_env}'). " \
                "Ignoring the contents of #{Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_URL}."
              )
              # rubocop:enable Layout/LineLength

              nil
            end
          end
      end

      # The settings.tracing.transport_options allows users to have full control over the settings used to
      # communicate with the agent. In the general case, we can't extract the configuration from this proc, but
      # in the specific case of the http and unix socket adapters we can, and we use this method together with the
      # `TransportOptionsResolver` to call the proc and extract its information.
      def transport_options
        return @transport_options if defined?(@transport_options)

        transport_options_proc = settings.tracing.transport_options

        @transport_options = TransportOptions.new

        if transport_options_proc.is_a?(Proc)
          begin
            transport_options_proc.call(TransportOptionsResolver.new(@transport_options))
          rescue NoMethodError => e
            if logger
              logger.debug do
                'Could not extract configuration from transport_options proc. ' \
                "Cause: #{e.class.name} #{e.message} Source: #{Array(e.backtrace).first}"
              end
            end

            # Reset the object; we shouldn't return the same one we passed into the proc as it may have
            # some partial configuration and we want all-or-nothing.
            @transport_options = TransportOptions.new
          end
        end

        @transport_options.freeze
      end

      # Used to contain information extracted from the transport_options proc (see #transport_options above)
      TransportOptions = Struct.new(:adapter, :hostname, :port, :timeout_seconds, :ssl, :uds_path)
      private_constant :TransportOptions

      # Used to extract information from the transport_options proc (see #transport_options above)
      class TransportOptionsResolver
        def initialize(transport_options)
          @transport_options = transport_options
        end

        def adapter(kind_or_custom_adapter, *args, **kwargs)
          case kind_or_custom_adapter
          when Datadog::Transport::Ext::HTTP::ADAPTER
            @transport_options.adapter = Datadog::Transport::Ext::HTTP::ADAPTER
            @transport_options.hostname = args[0] || kwargs[:hostname]
            @transport_options.port = args[1] || kwargs[:port]
            @transport_options.timeout_seconds = kwargs[:timeout]
            @transport_options.ssl = kwargs[:ssl]
          when Datadog::Transport::Ext::UnixSocket::ADAPTER
            @transport_options.adapter = Datadog::Transport::Ext::UnixSocket::ADAPTER
            @transport_options.uds_path = args[0] || kwargs[:uds_path]
          end

          nil
        end
      end
    end
  end
end
