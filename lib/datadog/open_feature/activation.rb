# frozen_string_literal: true

require_relative "agentless/configuration_source"
require_relative "component"
require_relative "configuration/agentless_endpoint"
require_relative "configuration/source"
require_relative "remote"

module Datadog
  module OpenFeature
    # Owns configuration delivery after an application adopts the provider.
    class Activation
      attr_reader :component, :failure, :provider

      def initialize(settings, agent_settings, remote, logger:, telemetry:)
        @settings = settings
        @agent_settings = agent_settings
        @remote = remote
        @logger = logger
        @telemetry = telemetry
        @component = nil
        @configuration_source = nil
        @failure = nil
        @provider = nil
        @activated = false
        @delivery_started = false
        @shutdown = false
        @mutex = Mutex.new
      end

      def activate(provider)
        @mutex.synchronize do
          return if @shutdown

          @provider = provider
          return @component if @activated && @delivery_started
          return if @activated

          @activated = true
          resolution = Configuration::Source.resolve(@settings.open_feature, logger: @logger)
          unless resolution.enabled?
            @failure = "Feature Flags are disabled"
            return
          end

          @component = Component.build(
            @settings,
            @agent_settings,
            resolution: resolution,
            on_configuration_change: ->(event) { configuration_changed(event) },
            logger: @logger,
            telemetry: @telemetry,
          )
          unless @component
            @failure = "Feature Flags are unavailable on this runtime"
            return
          end

          @delivery_started = start_delivery(resolution.source)
          @component if @delivery_started
        end
      end

      def activated?
        @mutex.synchronize { @activated }
      end

      def shutdown!
        configuration_source, component = @mutex.synchronize do
          return if @shutdown

          @shutdown = true
          [@configuration_source, @component]
        end

        configuration_source&.stop
        component&.shutdown!
      end

      private

      def start_delivery(source)
        case source
        when Configuration::Source::AGENTLESS
          start_agentless
        when Configuration::Source::REMOTE_CONFIG
          start_remote_configuration
        else
          @failure = "Feature Flags configuration source is unavailable"
          false
        end
      end

      def start_agentless
        component = @component
        return false unless component

        endpoint = Configuration::AgentlessEndpoint.build(
          site: @settings.site,
          environment: @settings.env,
          base_url: @settings.open_feature.agentless_base_url,
          logger: @logger,
        )
        unless endpoint
          @failure = "Feature Flags agentless endpoint is unavailable"
          return false
        end

        configuration_source = Agentless::ConfigurationSource.build(
          @settings,
          endpoint: endpoint,
          apply: ->(configuration) { component.reconfigure!(configuration) },
          logger: @logger,
        )
        unless configuration_source
          @failure = "Feature Flags agentless delivery could not start"
          return false
        end

        @configuration_source = configuration_source
        started = configuration_source.start
        @failure = "Feature Flags agentless delivery could not start" unless started
        started
      end

      def start_remote_configuration
        remote = @remote
        unless remote
          @failure = "Feature Flags Remote Configuration is unavailable"
          return false
        end

        remote.register(
          capabilities: Remote.capabilities,
          products: Remote.products,
          receivers: Remote.receivers(@telemetry),
        )
        remote.start
        true
      end

      def configuration_changed(event)
        provider = @mutex.synchronize { @provider }
        provider&.send(:configuration_changed, event)
      end
    end
  end
end
