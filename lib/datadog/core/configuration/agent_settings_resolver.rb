require 'uri'

require_relative 'settings'
require_relative 'ext'
require_relative '../transport/ext'

module Datadog
  module Core
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
      # DEV-2.0: The deprecated_for_removal_transport_configuration_proc should be removed.
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
          ) do
            def initialize(
              adapter:,
              ssl:,
              hostname:,
              port:,
              uds_path:,
              timeout_seconds:,
              deprecated_for_removal_transport_configuration_proc:
            )
              super(
                adapter,
                ssl,
                hostname,
                port,
                uds_path,
                timeout_seconds,
                deprecated_for_removal_transport_configuration_proc
              )
              freeze
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
          if transport_options.adapter == Datadog::Core::Transport::Ext::UnixSocket::ADAPTER
            return AgentSettings.new(
              adapter: Datadog::Core::Transport::Ext::UnixSocket::ADAPTER,
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

        def adapter
          if should_use_uds?
            Datadog::Core::Transport::Ext::UnixSocket::ADAPTER
          else
            Datadog::Core::Transport::Ext::HTTP::ADAPTER
          end
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
              friendly_name: "#{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_URL} environment variable",
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
              friendly_name: "#{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_URL} environment variable",
              value: parsed_http_url && parsed_http_url.port,
            ),
            try_parsing_as_integer(
              friendly_name: "#{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_PORT} environment variable",
              value: ENV[Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_PORT],
            )
          )
        end

        def try_parsing_as_integer(value:, friendly_name:)
          value =
            begin
              Integer(value) if value
            rescue ArgumentError, TypeError
              log_warning("Invalid value for #{friendly_name} (#{value.inspect}). Ignoring this configuration.")

              nil
            end

          DetectedConfiguration.new(friendly_name: friendly_name, value: value)
        end

        def ssl?
          transport_options.ssl ||
            (!parsed_url.nil? && parsed_url.scheme == 'https')
        end

        def hostname
          configured_hostname || (should_use_uds? ? nil : Datadog::Core::Configuration::Ext::Agent::HTTP::DEFAULT_HOST)
        end

        def port
          configured_port || (should_use_uds? ? nil : Datadog::Core::Configuration::Ext::Agent::HTTP::DEFAULT_PORT)
        end

        # Unix socket path in the file system
        def uds_path
          if mixed_http_and_uds?
            nil
          elsif parsed_url && unix_scheme?(parsed_url)
            path = parsed_url.to_s
            # Some versions of the built-in uri gem leave the original url untouched, and others remove the //, so this
            # supports both
            if path.start_with?('unix://')
              path.sub('unix://', '')
            else
              path.sub('unix:', '')
            end
          else
            uds_fallback
          end
        end

        # Defaults to +nil+, letting the adapter choose what default
        # works best in their case.
        def timeout_seconds
          transport_options.timeout_seconds
        end

        # In transport_options, we try to invoke the transport_options proc and get its configuration. In case that
        # doesn't work, we include the proc directly in the agent settings result.
        def deprecated_for_removal_transport_configuration_proc
          transport_options_settings if transport_options_settings.is_a?(Proc) && transport_options.adapter.nil?
        end

        def transport_options_settings
          @transport_options_settings ||= begin
            settings.tracing.transport_options if settings.respond_to?(:tracing) && settings.tracing
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
                File.exist?(Datadog::Core::Configuration::Ext::Agent::UnixSocket::DEFAULT_PATH)

              Datadog::Core::Configuration::Ext::Agent::UnixSocket::DEFAULT_PATH
            end
        end

        def should_use_uds?
          can_use_uds? && !mixed_http_and_uds?
        end

        def can_use_uds?
          parsed_url && unix_scheme?(parsed_url) ||
            # If no agent settings have been provided, we try to connect using a local unix socket.
            # We only do so if the socket is present when `ddtrace` runs.
            !uds_fallback.nil?
        end

        def parsed_url
          return @parsed_url if defined?(@parsed_url)

          unparsed_url_from_env = ENV[Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_URL]

          @parsed_url =
            if unparsed_url_from_env
              parsed = URI.parse(unparsed_url_from_env)

              if http_scheme?(parsed) || unix_scheme?(parsed)
                parsed
              else
                # rubocop:disable Layout/LineLength
                log_warning(
                  "Invalid URI scheme '#{parsed.scheme}' for #{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_URL} " \
                  "environment variable ('#{unparsed_url_from_env}'). " \
                  "Ignoring the contents of #{Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_URL}."
                )
                # rubocop:enable Layout/LineLength

                nil
              end
            end
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
            ". Using #{detected_configurations_in_priority_order.first.value.inspect} and ignoring other configuration."
          )
        end

        def log_warning(message)
          logger.warn(message) if logger
        end

        def http_scheme?(uri)
          ['http', 'https'].include?(uri.scheme)
        end

        # Expected to return nil (not false!) when it's not http
        def parsed_http_url
          parsed_url if parsed_url && http_scheme?(parsed_url)
        end

        def unix_scheme?(uri)
          uri.scheme == 'unix'
        end

        # When we have mixed settings for http/https and uds, we print a warning and ignore the uds settings
        def mixed_http_and_uds?
          return @mixed_http_and_uds if defined?(@mixed_http_and_uds)

          @mixed_http_and_uds = (configured_hostname || configured_port) && can_use_uds?

          if @mixed_http_and_uds
            warn_if_configuration_mismatch(
              [
                DetectedConfiguration.new(
                  friendly_name: 'configuration of hostname/port for http/https use',
                  value: "hostname: '#{hostname}', port: '#{port}'",
                ),
                DetectedConfiguration.new(
                  friendly_name: 'configuration for unix domain socket',
                  value: parsed_url.to_s,
                ),
              ]
            )
          end

          @mixed_http_and_uds
        end

        # The settings.tracing.transport_options allows users to have full control over the settings used to
        # communicate with the agent. In the general case, we can't extract the configuration from this proc, but
        # in the specific case of the http and unix socket adapters we can, and we use this method together with the
        # `TransportOptionsResolver` to call the proc and extract its information.
        def transport_options
          return @transport_options if defined?(@transport_options)

          transport_options_proc = transport_options_settings

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

        # Represents a given configuration value and where we got it from
        class DetectedConfiguration
          attr_reader :friendly_name, :value

          def initialize(friendly_name:, value:)
            @friendly_name = friendly_name
            @value = value
            freeze
          end

          def value?
            !value.nil?
          end
        end
        private_constant :DetectedConfiguration

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
            when Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
              @transport_options.adapter = Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
              @transport_options.hostname = args[0] || kwargs[:hostname]
              @transport_options.port = args[1] || kwargs[:port]
              @transport_options.timeout_seconds = kwargs[:timeout]
              @transport_options.ssl = kwargs[:ssl]
            when Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
              @transport_options.adapter = Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
              @transport_options.uds_path = args[0] || kwargs[:uds_path]
            end

            nil
          end
        end
      end
    end
  end
end
