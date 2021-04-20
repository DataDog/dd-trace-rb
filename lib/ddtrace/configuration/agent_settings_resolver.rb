require 'uri'

module Datadog
  module Configuration
    # This class unifies all the different ways that users can configure how we talk to the agent.
    #
    # Whenever there is a conflict (different configurations are provided in different orders), it MUST warn the users
    # about it and pick a value based on the following priority: code > environment variable > defaults.
    class AgentSettingsResolver
      private

      attr_reader \
        :logger

      public

      def initialize(logger: Datadog.logger)
        @logger = logger
      end

      def call
        {
          adapter: :http,
          ssl: ssl?,
          hostname: hostname,
          port: port,
        }
      end

      private

      def hostname
        hostname_from_env = ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST]

        if parsed_url
          if hostname_from_env && hostname_from_env != parsed_url.hostname
            logger.warn(
              "Configuration mismatch: both the #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL} ('#{unparsed_url_from_env}') " \
              "and the #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST} ('#{hostname_from_env}') were specified, " \
              "and their values differ. Using #{unparsed_url_from_env}."
            )
          end

          parsed_url.hostname
        else
          hostname_from_env || Datadog::Ext::Transport::HTTP::DEFAULT_HOST
        end
      end

      def port
        port_from_env = ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT]

        if parsed_url
          if port_from_env && port_from_env != parsed_url.port
            logger.warn(
              "Configuration mismatch: both the #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL} ('#{unparsed_url_from_env}') " \
              "and the #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT} ('#{port_from_env}') were specified, " \
              "and their values differ. Using #{unparsed_url_from_env}."
            )
          end

          return parsed_url.port
        end

        default_value = Datadog::Ext::Transport::HTTP::DEFAULT_PORT

        if port_from_env
          begin
            return Integer(port_from_env)
          rescue ArgumentError
            logger.warn("Invalid value for #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT} environment variable ('#{port_from_env}'). Falling back to default value #{default_value}.")
          end
        end

        default_value
      end

      def ssl?
        !parsed_url.nil? && parsed_url.scheme == "https"
      end

      def parsed_url
        return @parsed_url if defined?(@parsed_url)

        result = nil

        if unparsed_url_from_env
          result = URI.parse(unparsed_url_from_env)

          unless ["http", "https"].include?(result.scheme)
            logger.warn(
              "Invalid URI scheme '#{result.scheme}' for #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL} " \
              "environment variable ('#{unparsed_url_from_env}'). " \
              "Ignoring the contents of #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL}."
            )

            result = nil
          end
        end

        @parsed_url = result
      end

      # NOTE: This should only be used AFTER parsing, via `#parsed_url`. The only other use-case where this can be used
      # directly without parsing, is when displaying in warning messages, to show users what it actually contains.
      def unparsed_url_from_env
        @unparsed_url_from_env ||= ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL]
      end
    end
  end
end
