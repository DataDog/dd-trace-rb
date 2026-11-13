# frozen_string_literal: true

require_relative "agentless/configuration_source"
require_relative "component"
require_relative "configuration/agentless_endpoint"
require_relative "configuration/source"
require_relative "flag_selection_reporter"
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
        @flag_selection_reporter = FlagSelectionReporter.new(logger: logger, telemetry: telemetry)
        @claimed_flag_selection = nil
        @flag_selection_dropped = false
        @component = nil
        @configuration_source = nil
        @delivery_source = nil
        @remote_receivers = nil
        @failure = nil
        @providers = {}.compare_by_identity
        @activated = false
        @delivery_started = false
        @shutdown = false
        @mutex = Mutex.new
      end

      def activate(provider)
        @mutex.synchronize do
          return if @shutdown
          return unless open_feature_available?

          @providers[provider] = true
          flag_selection = provider.send(:flag_selection)
          if @activated
            return unless @delivery_started

            report_joining_flag_selection(flag_selection)
            return @component
          end

          resolution = Configuration::Source.resolve(@settings, logger: @logger)
          component = activate_delivery(resolution, flag_selection)
          if flag_selection && @delivery_started && @delivery_source == Configuration::Source::REMOTE_CONFIG
            @flag_selection_reporter.warn_remote_config
          end
          component
        end
      end

      def startup!
        start!
        OpenFeature.reattach(self)
      rescue => e
        # Feature Flags is optional and must never interrupt library startup.
        report_failure(e, "Feature Flags delivery failed to start")
      end

      def start!
        @mutex.synchronize do
          return if @shutdown || @activated
          return unless open_feature_available?

          resolution = Configuration::Source.resolve(@settings, logger: @logger)
          return unless resolution.enabled? && resolution.source == Configuration::Source::REMOTE_CONFIG

          activate_delivery(resolution, nil)
        end
      end

      def activated?
        @mutex.synchronize { @activated }
      end

      def providers
        @mutex.synchronize { @providers.keys }
      end

      def after_fork
        FlagSelectionReporter.reset_once_guards
        inherited_providers, component = @mutex.synchronize do
          @shutdown ? [[], nil] : [@providers.keys, @component]
        end
        inherited_providers.each { |provider| provider.send(:after_fork, component) }

        configuration_source, dropped_flag_selection = @mutex.synchronize do
          if @shutdown || !@delivery_started
            [nil, nil]
          elsif @delivery_source == Configuration::Source::REMOTE_CONFIG
            [@remote, nil]
          else
            [@configuration_source, (@claimed_flag_selection if @flag_selection_dropped)]
          end
        end

        # The child keeps loading the full configuration, so it counts the inherited drop for its own process.
        # It logs nothing: "not sent" is logged once per provider init, and no provider initializes here.
        @flag_selection_reporter.count_dropped(dropped_reason(dropped_flag_selection)) if dropped_flag_selection
        configuration_source&.start
        nil
      rescue => e
        # Feature Flags is optional and must never interrupt other post-fork handlers.
        report_failure(e, "Feature Flags delivery failed to restart after fork")
      end

      def deactivate(provider)
        configuration_source, component = @mutex.synchronize do
          return if @shutdown
          return unless @providers.delete(provider)
          return unless @providers.empty?
          if @delivery_source == Configuration::Source::REMOTE_CONFIG && @delivery_started
            # Remote Configuration is process-scoped and may already hold configuration needed by the next provider.
            @logger.debug { "Feature Flags: provider detached; process-scoped Remote Configuration remains active" }
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
          !@providers.empty? && !!component&.configuration_received?
        end
        configuration_changed(Component::CONFIGURATION_LOST) if configuration_received
        component&.shutdown!
      end

      private

      def report_failure(error, description)
        @logger.error("#{description}: #{error.class}: #{error.message}")
        @telemetry.report(error, description: description)
      end

      def open_feature_available?
        @settings.respond_to?(:open_feature) && @settings.respond_to?(:feature_flags)
      end

      def activate_delivery(resolution, flag_selection)
        @activated = true
        unless resolution.enabled?
          @failure = "Feature Flags are disabled"
          @logger.debug do
            reason = @settings.feature_flags.enabled ? "the resolved configuration source is offline" : "feature_flags.enabled is false"
            "Feature Flags: disabled because #{reason}"
          end
          return
        end

        @logger.debug { "Feature Flags: configuration source is #{resolution.source}" }
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
        @delivery_started = start_delivery(resolution.source, flag_selection)
        return component if @delivery_started

        component.shutdown!
        @component = nil
        @delivery_source = nil
        nil
      rescue
        configuration_source = @configuration_source
        failed_component = @component
        @component = nil
        @configuration_source = nil
        @delivery_source = nil
        @activated = false
        @delivery_started = false
        @failure = nil
        begin
          configuration_source&.stop
        ensure
          failed_component&.shutdown!
        end
        raise
      end

      def start_delivery(source, flag_selection)
        case source
        when Configuration::Source::AGENTLESS
          start_agentless(flag_selection)
        when Configuration::Source::REMOTE_CONFIG
          start_remote_configuration
        else
          @failure = "Feature Flags configuration source is unavailable"
          false
        end
      end

      def start_agentless(flag_selection)
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

        selected_endpoint = endpoint.with_flag_selection(flag_selection) if flag_selection && !flag_selection.dropped?
        configuration_source = Agentless::ConfigurationSource.build(
          @settings,
          endpoint: selected_endpoint || endpoint,
          apply: ->(configuration) { component.reconfigure!(configuration) },
          logger: @logger,
          flag_selection_reporter: @flag_selection_reporter,
        )
        unless configuration_source
          @failure = "Feature Flags agentless delivery could not start"
          return false
        end

        @configuration_source = configuration_source

        @logger.debug do
          agentless = @settings.feature_flags.agentless
          sdk_env = @settings.env ? "sdk_env=#{@settings.env.inspect}" : "sdk_env is unset"
          requested_env = if endpoint.managed?
            @settings.env ? "requested_env=#{@settings.env.inspect}" : "requested_env is unset"
          else
            "requested_env is not sent (custom endpoint)"
          end
          "Feature Flags: starting agentless configuration source at #{endpoint.origin} " \
            "(#{sdk_env}, #{requested_env}, " \
            "poll interval #{agentless.poll_interval_seconds}s, request timeout #{agentless.request_timeout_seconds}s)"
        end

        started = configuration_source.start
        if started
          claim_flag_selection(flag_selection, selected_endpoint)
        else
          @failure = "Feature Flags agentless delivery could not start"
        end
        started
      end

      # Every provider shares one agentless source, so the provider that starts it decides what it requests.
      # The claim lasts until delivery stops: the next start claims again.
      def claim_flag_selection(flag_selection, selected_endpoint)
        @claimed_flag_selection = flag_selection
        @flag_selection_dropped = false
        return unless flag_selection && selected_endpoint.nil?

        @flag_selection_dropped = true
        report_flag_selection_not_sent(flag_selection)
      end

      def report_joining_flag_selection(flag_selection)
        if @delivery_source == Configuration::Source::REMOTE_CONFIG
          @flag_selection_reporter.warn_remote_config if flag_selection
        elsif flag_selection != @claimed_flag_selection
          # A different selection is not used: it reports its own drop, and warns only if it would load
          # other flags, since a dropped selection and no selection both load every flag.
          drop_reason = flag_selection&.drop_reason
          @flag_selection_reporter.report_dropped(drop_reason) if drop_reason
          joining_flags = flag_selection unless flag_selection&.dropped?
          loaded_flags = @claimed_flag_selection unless @flag_selection_dropped
          @flag_selection_reporter.warn_selection_differs unless joining_flags == loaded_flags
        elsif flag_selection && @flag_selection_dropped
          report_flag_selection_not_sent(flag_selection)
        end
      end

      def report_flag_selection_not_sent(flag_selection)
        drop_reason = flag_selection.drop_reason
        if drop_reason
          @flag_selection_reporter.report_dropped(drop_reason)
        else
          @flag_selection_reporter.report_url_too_long
        end
      end

      def dropped_reason(flag_selection)
        flag_selection.drop_reason || Configuration::FlagSelection::TOO_MANY_VALUES
      end

      def start_remote_configuration
        remote = @remote
        unless remote
          @failure = "Feature Flags Remote Configuration is unavailable"
          @logger.warn(
            "#{@failure}. To enable Remote Configuration, " \
              "see https://docs.datadoghq.com/remote_configuration/.",
          )
          return false
        end

        receivers = @remote_receivers ||= Remote.receivers(
          @telemetry,
          component_provider: -> { @mutex.synchronize { @component } },
          logger: @logger,
        )
        remote.register(
          capabilities: Remote.capabilities,
          products: Remote.products,
          receivers: receivers,
        )
        remote.start
        @logger.debug do
          sdk_env = @settings.env ? "sdk_env=#{@settings.env.inspect}" : "sdk_env is unset"
          "Feature Flags: started Remote Configuration source (#{sdk_env}) using Datadog Agent"
        end
        true
      end

      def configuration_changed(event)
        providers = @mutex.synchronize { @providers.keys }
        providers.each { |provider| provider.send(:configuration_changed, event) }
      end
    end
  end
end
