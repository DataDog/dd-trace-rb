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
        :logger,
        :settings

      public

      def initialize(settings, logger: Datadog.logger)
        @settings = settings
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
        detected_configurations_in_priority_order = [
          DetectedConfiguration.new(
            friendly_name: "'settings.tracer.hostname'",
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
        ].select(&:value?)

        if detected_configurations_in_priority_order.any?
          warn_if_configuration_mismatch(detected_configurations_in_priority_order)

          # The configurations above are listed in priority, so we only need to look at the first; if there's more than
          # one, we emit a warning above
          detected_configurations_in_priority_order.first.value
        else
          Datadog::Ext::Transport::HTTP::DEFAULT_HOST
        end
      end

      def port
        port_from_env = ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT]
        parsed_port_from_env =
          if port_from_env
            begin
              Integer(port_from_env)
            rescue ArgumentError
              logger.warn(
                "Invalid value for #{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT} environment variable ('#{port_from_env}'). " \
                "Ignoring this configuration."
              )
            end
          end

        detected_configurations_in_priority_order = [
          DetectedConfiguration.new(
            friendly_name: "#{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL} environment variable",
            value: parsed_url && parsed_url.port
          ),
          DetectedConfiguration.new(
            friendly_name: "#{Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT} environment variable",
            value: parsed_port_from_env
          )
        ].select(&:value?)

        if detected_configurations_in_priority_order.any?
          warn_if_configuration_mismatch(detected_configurations_in_priority_order)

          # The configurations above are listed in priority, so we only need to look at the first; if there's more than
          # one, we emit a warning above
          detected_configurations_in_priority_order.first.value
        else
          Datadog::Ext::Transport::HTTP::DEFAULT_PORT
        end
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

      def warn_if_configuration_mismatch(detected_configurations_in_priority_order)
        return unless detected_configurations_in_priority_order.map(&:value).uniq.size > 1

        logger.warn(
          "Configuration mismatch: values differ between " +
          detected_configurations_in_priority_order.map { |config|
            "#{config.friendly_name} ('#{config.value}')"
          }.join(" and ") +
          ". Using '#{detected_configurations_in_priority_order.first.value}'."
        )
      end

      class DetectedConfiguration < Struct.new(:friendly_name, :value)
        def initialize(friendly_name:, value:)
          super(friendly_name, value)
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
