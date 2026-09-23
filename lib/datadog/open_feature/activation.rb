# frozen_string_literal: true

require_relative "agentless/configuration_source"
require_relative "component"
require_relative "configuration/agentless_endpoint"
require_relative "configuration/source"
require_relative "remote"

module Datadog
  module OpenFeature
    # Owns eager Remote Configuration and lazy agentless delivery activation.
    class Activation
      attr_reader :component, :failure

      def initialize(settings, agent_settings, remote, logger:, telemetry:)
        @settings = settings
        @agent_settings = agent_settings
        @remote = remote
        @logger = logger
        @telemetry = telemetry
        @component = nil
        @configuration_source = nil
        @delivery_source = nil
        @failure = nil
        @providers = []
        @activated = false
        @delivery_started = false
        @shutdown = false
        @mutex = Mutex.new
      end

      def activate(provider)
        @mutex.synchronize do
          return if @shutdown
          return unless open_feature_available?

          @providers << provider unless @providers.any? { |active_provider| active_provider.equal?(provider) }
          return @component if @activated && @delivery_started
          return if @activated

          resolution = Configuration::Source.resolve(@settings, logger: @logger)
          activate_delivery(resolution)
        end
      end

      def start!
        @mutex.synchronize do
          return if @shutdown || @activated
          return unless open_feature_available?

          resolution = Configuration::Source.resolve(@settings, logger: @logger)
          return unless resolution.enabled? && resolution.source == Configuration::Source::REMOTE_CONFIG

          activate_delivery(resolution)
        end
      end

      def activated?
        @mutex.synchronize { @activated }
      end

      def providers
        @mutex.synchronize { @providers.dup }
      end

      # Timer-driven delivery has no operation in the child that can restart its inherited worker.
      def after_fork
        configuration_source = @mutex.synchronize do
          if @shutdown || !@delivery_started
            nil
          else
            @configuration_source
          end
        end

        configuration_source&.start
        nil
      end

      def deactivate(provider)
        configuration_source, component = @mutex.synchronize do
          return if @shutdown
          provider_index = @providers.index { |active_provider| active_provider.equal?(provider) }
          return unless provider_index

          @providers.delete_at(provider_index)
          return unless @providers.empty?
          if @delivery_source == Configuration::Source::REMOTE_CONFIG && @delivery_started
            # Remote Configuration is process-scoped and may already hold configuration needed by the next provider.
            [nil, nil]
          else
            previous_source = @configuration_source
            previous_component = @component
            @component = nil
            @configuration_source = nil
            @delivery_source = nil
            @activated = false
            @delivery_started = false
            @failure = nil
            [previous_source, previous_component]
          end
        end

        configuration_source&.stop
        component&.shutdown!
      end

      def shutdown!
        configuration_source, component = @mutex.synchronize do
          return if @shutdown

          @shutdown = true
          [@configuration_source, @component]
        end

        configuration_source&.stop
        configuration_received = @mutex.synchronize do
          !@providers.empty? && (component&.configuration_received? || false)
        end
        configuration_changed(Component::CONFIGURATION_LOST) if configuration_received
        component&.shutdown!
      end

      private

      def open_feature_available?
        @settings.respond_to?(:open_feature) && @settings.respond_to?(:feature_flags)
      end

      def activate_delivery(resolution)
        @activated = true
        unless resolution.enabled?
          @failure = "Feature Flags are disabled"
          return
        end

        component = Component.build(
          @settings,
          @agent_settings,
          resolution: resolution,
          on_configuration_change: ->(event) { configuration_changed(event) },
          logger: @logger,
          telemetry: @telemetry,
        )
        unless component
          @failure = "Feature Flags are unavailable on this runtime"
          return
        end

        @component = component
        @delivery_source = resolution.source
        @delivery_started = start_delivery(resolution.source)
        return component if @delivery_started

        component.shutdown!
        @component = nil
        @delivery_source = nil
        nil
      end

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
          base_url: @settings.feature_flags.agentless.base_url,
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
          @logger.warn(
            "#{@failure}. To enable Remote Configuration, " \
              "see https://docs.datadoghq.com/remote_configuration/."
          )
          return false
        end

        remote.register(
          capabilities: Remote.capabilities,
          products: Remote.products,
          receivers: Remote.receivers(
            @telemetry,
            component_provider: -> { @mutex.synchronize { @component } },
          ),
        )
        remote.start
        true
      end

      def configuration_changed(event)
        providers = @mutex.synchronize { @providers.dup }
        providers.each { |provider| provider.send(:configuration_changed, event) }
      end
    end
  end
end
