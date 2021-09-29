# typed: false
require 'uri'

require 'ddtrace/ext/transport'
require 'ddtrace/configuration/settings'

module Datadog
  module Configuration
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
    # rubocop:disable Metrics/ClassLength
    class AgentSettingsResolver
      AgentSettings = \
        Struct.new(
          :adapter,
          :ssl,
          :hostname,
          :port,
          :uds_path,
          :timeout_seconds,
          :deprecated_for_removal_transport_configuration_proc,
          :deprecated_for_removal_transport_configuration_options
        ) do
          def initialize(
            adapter:,
            ssl:,
            hostname:,
            port:,
            uds_path:,
            timeout_seconds:,
            deprecated_for_removal_transport_configuration_proc:,
            deprecated_for_removal_transport_configuration_options:
          )
            super(
              adapter,
              ssl,
              hostname,
              port,
              uds_path,
              timeout_seconds,
              deprecated_for_removal_transport_configuration_proc,
              deprecated_for_removal_transport_configuration_options,
            )
            freeze
          end

          def merge(**member_values)
            new_struct = dup

            member_values.each do |member, value|
              new_struct[member] = value
            end

            new_struct
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
          deprecated_for_removal_transport_configuration_options: deprecated_for_removal_transport_configuration_options
        )
      end

      def adapter
        # If no agent settings have been provided, we try to connect using a local unix socket.
        # We only do so if the socket is present when `ddtrace` runs.
        if should_use_uds_fallback?
          Ext::Transport::UnixSocket::ADAPTER
        else
          Ext::Transport::HTTP::ADAPTER
        end
      end

      def configured_hostname
        return @configured_hostname if defined?(@configured_hostname)

        @configured_hostname = pick_from(
          DetectedConfiguration.new(
            friendly_name: "'c.tracer.hostname'",
            value: settings.tracer.hostname
          ),
          DetectedConfiguration.new(
            friendly_name: "#{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL} environment variable",
            value: parsed_url && parsed_url.hostname
          ),
          DetectedConfiguration.new(
            friendly_name: "#{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST} environment variable",
            value: ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST]
          )
        )
      end

      def configured_port
        return @configured_port if defined?(@configured_port)

        port_from_env = ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT]
        parsed_port_from_env =
          if port_from_env
            begin
              Integer(port_from_env)
            rescue ArgumentError
              log_warning(
                "Invalid value for #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT} environment variable " \
                "('#{port_from_env}'). Ignoring this configuration."
              )
            end
          end

        @configured_port = pick_from(
          DetectedConfiguration.new(
            friendly_name: '"c.tracer.port"',
            value: settings.tracer.port
          ),
          DetectedConfiguration.new(
            friendly_name: "#{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL} environment variable",
            value: parsed_url && parsed_url.port
          ),
          DetectedConfiguration.new(
            friendly_name: "#{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT} environment variable",
            value: parsed_port_from_env
          )
        )
      end

      def ssl?
        !parsed_url.nil? && parsed_url.scheme == 'https'
      end

      def hostname
        configured_hostname || (should_use_uds_fallback? ? nil : Datadog::Ext::Transport::HTTP::DEFAULT_HOST)
      end

      def port
        configured_port || (should_use_uds_fallback? ? nil : Datadog::Ext::Transport::HTTP::DEFAULT_PORT)
      end

      # Unix socket path in the file system
      def uds_path
        uds_fallback
      end

      # Defaults to +nil+, letting the adapter choose what default
      # works best in their case.
      def timeout_seconds
        nil
      end

      def deprecated_for_removal_transport_configuration_proc
        settings.tracer.transport_options if settings.tracer.transport_options.is_a?(Proc)
      end

      def deprecated_for_removal_transport_configuration_options
        options = settings.tracer.transport_options

        if options.is_a?(Hash) && !options.empty?
          log_warning(
            'Configuring the tracer via a c.tracer.transport_options hash is deprecated for removal in a future ' \
            "ddtrace version (c.tracer.transport_options contained '#{options.inspect}')."
          )

          options
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
             deprecated_for_removal_transport_configuration_options.nil? &&
             File.exist?(Ext::Transport::UnixSocket::DEFAULT_PATH)

            Ext::Transport::UnixSocket::DEFAULT_PATH
          end
      end

      def should_use_uds_fallback?
        uds_fallback != nil
      end

      def parsed_url
        return @parsed_url if defined?(@parsed_url)

        @parsed_url =
          if unparsed_url_from_env
            parsed = URI.parse(unparsed_url_from_env)

            if %w[http https].include?(parsed.scheme)
              parsed
            else
              log_warning(
                "Invalid URI scheme '#{parsed.scheme}' for #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL} " \
                "environment variable ('#{unparsed_url_from_env}'). " \
                "Ignoring the contents of #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL}."
              )

              nil
            end
          end
      end

      # NOTE: This should only be used AFTER parsing, via `#parsed_url`. The only other use-case where this can be used
      # directly without parsing, is when displaying in warning messages, to show users what it actually contains.
      def unparsed_url_from_env
        @unparsed_url_from_env ||= ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL]
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
            .map { |config| "#{config.friendly_name} ('#{config.value}')" }.join(' and ')}" \
          ". Using '#{detected_configurations_in_priority_order.first.value}'."
        )
      end

      def log_warning(message)
        logger.warn(message) if logger
      end

      DetectedConfiguration = Struct.new(:friendly_name, :value) do
        def initialize(friendly_name:, value:)
          super(friendly_name, value)
          freeze
        end

        def value?
          !value.nil?
        end
      end
      private_constant :DetectedConfiguration

      # NOTE: Due to... legacy reasons... Some classes like having an `AgentSettings` instance to fall back to.
      # Because we generate this instance with an empty instance of `Settings`, the resulting `AgentSettings` below
      # represents only settings specified via environment variables + the usual defaults.
      #
      # YOU DO NOT WANT TO USE THE BELOW INSTANCE ON ANY NEWLY WRITTEN CODE, as it ignores any settings specified
      # by users via `Datadog.configure`.
      ENVIRONMENT_AGENT_SETTINGS = call(Settings.new, logger: nil)
    end
    # rubocop:enable Metrics/ClassLength
  end
end
