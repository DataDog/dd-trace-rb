# frozen_string_literal: true

require 'forwardable'

module Datadog
  module Core
    module Configuration
      # Mixin with common functionality for AgentSettingsResolver classes.
      module AgentSettingsResolverCommon
        extend Forwardable

        # Allows us to reference an instance var in the mixin consumer safely
        # here.
        def_delegator :logging_delegate, :logger

        BaseAgentSettings = \
          Struct.new(
            :adapter,
            :ssl,
            :hostname,
            :port,
            :uds_path,
            :timeout_seconds,
          ) do
            def initialize(
              adapter:,
              ssl:,
              hostname:,
              port:,
              uds_path:,
              timeout_seconds:
            )
              super(
                adapter,
                ssl,
                hostname,
                port,
                uds_path,
                timeout_seconds
              )
              freeze
            end
          end

        def log_warning(message)
          logger.warn(message) if logger
        end

        # The mixin consumer should define a logger as a private attr. If not,
        # we fall back to a default
        def logging_delegate
          return self if defined?(@logger) || respond_to?(:logger)

          Datadog.logger
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

        def adapter
          if should_use_uds? && !mixed_http_and_uds?
            Datadog::Transport::Ext::UnixSocket::ADAPTER
          else
            Datadog::Transport::Ext::HTTP::ADAPTER
          end
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

        def should_use_uds?
          parsed_url && unix_scheme?(parsed_url) ||
            # If no agent settings have been provided, we try to connect using a local unix socket.
            # We only do so if the socket is present when `ddtrace` runs.
            !uds_fallback.nil?
        end

        # Expected to return nil (not false!) when it's not http
        def parsed_http_url
          parsed_url if parsed_url && http_scheme?(parsed_url)
        end

        def http_scheme?(uri)
          ['http', 'https'].include?(uri.scheme)
        end

        def unix_scheme?(uri)
          uri.scheme == 'unix'
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
      end
    end
  end
end
