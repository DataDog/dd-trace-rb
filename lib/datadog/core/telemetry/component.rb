# frozen_string_literal: true

require_relative 'emitter'
require_relative 'event'
require_relative 'metrics_manager'
require_relative 'worker'
require_relative 'logging'
require_relative 'transport/http'

require_relative '../configuration/ext'
require_relative '../configuration/agentless_settings_resolver'
require_relative '../utils/forking'

module Datadog
  module Core
    module Telemetry
      # Telemetry entry point, coordinates sending telemetry events at
      # various points in application lifecycle.
      #
      # @api private
      class Component
        ENDPOINT_COLLECTION_MESSAGE_LIMIT = 300

        attr_reader :enabled
        attr_reader :logger
        attr_reader :transport
        attr_reader :worker
        attr_reader :settings
        attr_reader :agent_settings
        attr_reader :metrics_manager

        # Alias for consistency with other components.
        # TODO Remove +enabled+ method
        alias_method :enabled?, :enabled

        include Core::Utils::Forking
        include Telemetry::Logging

        def self.build(settings, agent_settings, logger)
          enabled = settings.telemetry.enabled
          agentless_enabled = settings.telemetry.agentless_enabled

          if agentless_enabled && settings.api_key.nil?
            enabled = false
            logger.debug { 'Telemetry disabled. Agentless telemetry requires a DD_API_KEY variable to be set.' }
          end

          Telemetry::Component.new(
            settings: settings,
            agent_settings: agent_settings,
            enabled: enabled,
            logger: logger,
          )
        end

        # @param enabled [Boolean] Determines whether telemetry events should be sent to the API
        def initialize( # standard:disable Metrics/MethodLength
          settings:,
          agent_settings:,
          logger:,
          enabled:
        )
          @enabled = enabled
          @log_collection_enabled = settings.telemetry.log_collection_enabled
          @logger = logger

          @metrics_manager = MetricsManager.new(
            enabled: @enabled && settings.telemetry.metrics_enabled,
            aggregation_interval: settings.telemetry.metrics_aggregation_interval_seconds,
          )

          @stopped = false

          return unless @enabled

          @transport = if settings.telemetry.agentless_enabled
            # We don't touch the `agent_settings` since we still want the telemetry payloads to refer to the original
            # settings, even though the telemetry itself may be using a different path.
            telemetry_specific_agent_settings = Core::Configuration::AgentlessSettingsResolver.call(
              settings,
              host_prefix: 'instrumentation-telemetry-intake',
              url_override: settings.telemetry.agentless_url_override,
              url_override_source: 'c.telemetry.agentless_url_override',
              logger: logger,
            )
            Telemetry::Transport::HTTP.agentless_telemetry(
              agent_settings: telemetry_specific_agent_settings,
              logger: logger,
              # api_key should have already validated to be
              # not nil by +build+ method above.
              api_key: settings.api_key,
            )
          else
            Telemetry::Transport::HTTP.agent_telemetry(
              agent_settings: agent_settings, logger: logger,
            )
          end

          @worker = Telemetry::Worker.new(
            enabled: @enabled,
            heartbeat_interval_seconds: settings.telemetry.heartbeat_interval_seconds,
            extended_heartbeat_interval_seconds: settings.telemetry.extended_heartbeat_interval_seconds,
            metrics_aggregation_interval_seconds: settings.telemetry.metrics_aggregation_interval_seconds,
            emitter: Emitter.new(
              @transport,
              logger: @logger,
              debug: settings.telemetry.debug,
            ),
            metrics_manager: @metrics_manager,
            dependency_collection: settings.telemetry.dependency_collection,
            logger: logger,
            shutdown_timeout: settings.telemetry.shutdown_timeout_seconds,
          )

          @agent_settings = agent_settings
        end

        def disable!
          @enabled = false
          @worker&.enabled = false
        end

        def start(initial_event_is_change = false, components:)
          return unless enabled?

          initial_event = if initial_event_is_change
            Event::SynthAppClientConfigurationChange.new(
              components: components,
            )
          else
            Event::AppStarted.new(
              components: components,
            )
          end

          extended_heartbeat_event = Event::AppExtendedHeartbeat.new(
            components: components,
          )

          @worker.start(initial_event, extended_heartbeat_event: extended_heartbeat_event)
        end

        def shutdown!
          return if @stopped

          if defined?(@worker)
            @worker&.stop(true)
          end

          @stopped = true
        end

        def emit_closing!
          return unless enabled?

          @worker.enqueue(Event::AppClosing.new)
        end

        def integrations_change!
          return unless enabled?

          @worker.enqueue(Event::AppIntegrationsChange.new)
        end

        def log!(event)
          return unless enabled? && @log_collection_enabled

          @worker.enqueue(event)
        end

        # Wait for the worker to send out all events that have already
        # been queued, up to 15 seconds. Returns whether all events have
        # been flushed, or nil if telemetry is disabled.
        #
        # @api private
        def flush(timeout: nil)
          return unless enabled?

          @worker.flush(timeout: timeout)
        end

        # Report configuration changes caused by Remote Configuration.
        def client_configuration_change!(changes)
          return unless enabled?

          @worker.enqueue(Event::AppClientConfigurationChange.new(changes, 'remote_config'))
        end

        # Report application endpoints
        def app_endpoints_loaded(endpoints, page_size: ENDPOINT_COLLECTION_MESSAGE_LIMIT)
          return unless enabled?

          endpoints.each_slice(page_size).with_index do |endpoints_slice, i|
            @worker.enqueue(Event::AppEndpointsLoaded.new(endpoints_slice, is_first: i.zero?))
          end
        end

        # Increments a count metric.
        def inc(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.inc(namespace, metric_name, value, tags: tags, common: common)
        end

        # Decremenets a count metric.
        def dec(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.dec(namespace, metric_name, value, tags: tags, common: common)
        end

        # Tracks gauge metric.
        def gauge(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.gauge(namespace, metric_name, value, tags: tags, common: common)
        end

        # Tracks rate metric.
        def rate(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.rate(namespace, metric_name, value, tags: tags, common: common)
        end

        # Tracks distribution metric.
        def distribution(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.distribution(namespace, metric_name, value, tags: tags, common: common)
        end

        # When a fork happens, we generally need to do two things inside the
        # child proess:
        # 1. Restart the worker.
        # 2. Discard any events and metrics that were submitted in the
        #    parent process (because they will be sent out in the parent
        #    process, sending them in the child would cause duplicate
        #    submission).
        def after_fork
          # We cannot simply create a new instance of metrics manager because
          # it is referenced from other objects (e.g. the worker).
          # We must reset the existing instance.
          @metrics_manager.clear

          worker&.send(:after_fork_monkey_patched)
        end
      end
    end
  end
end
