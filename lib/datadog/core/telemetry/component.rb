# frozen_string_literal: true

require_relative 'emitter'
require_relative 'event'
require_relative 'http/transport'
require_relative 'metrics_manager'
require_relative 'worker'
require_relative 'logging'

require_relative '../configuration/ext'
require_relative '../utils/forking'

module Datadog
  module Core
    module Telemetry
      # Telemetry entrypoint, coordinates sending telemetry events at various points in app lifecycle.
      class Component
        attr_reader :enabled

        include Core::Utils::Forking
        include Telemetry::Logging

        def self.build(settings, agent_settings, logger)
          enabled = settings.telemetry.enabled
          agentless_enabled = settings.telemetry.agentless_enabled

          if !agentless_enabled && agent_settings.adapter != Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
            enabled = false
            logger.debug { "Telemetry disabled. Agent network adapter not supported: #{agent_settings.adapter}" }
          end

          if agentless_enabled && settings.api_key.nil?
            enabled = false
            logger.debug { 'Telemetry disabled. Agentless telemetry requires an DD_API_KEY variable to be set.' }
          end

          transport = if agentless_enabled
                        Datadog::Core::Telemetry::Http::Transport.build_agentless_transport(
                          api_key: settings.api_key,
                          dd_site: settings.site,
                          url_override: settings.telemetry.agentless_url_override
                        )
                      else
                        Datadog::Core::Telemetry::Http::Transport.build_agent_transport(agent_settings)
                      end

          Telemetry::Component.new(
            http_transport: transport,
            enabled: enabled,
            metrics_enabled: enabled && settings.telemetry.metrics_enabled,
            heartbeat_interval_seconds: settings.telemetry.heartbeat_interval_seconds,
            metrics_aggregation_interval_seconds: settings.telemetry.metrics_aggregation_interval_seconds,
            dependency_collection: settings.telemetry.dependency_collection,
            shutdown_timeout_seconds: settings.telemetry.shutdown_timeout_seconds,
            log_collection_enabled: settings.telemetry.log_collection_enabled
          )
        end

        # @param enabled [Boolean] Determines whether telemetry events should be sent to the API
        # @param metrics_enabled [Boolean] Determines whether telemetry metrics should be sent to the API
        # @param heartbeat_interval_seconds [Float] How frequently heartbeats will be reported, in seconds.
        # @param metrics_aggregation_interval_seconds [Float] How frequently metrics will be aggregated, in seconds.
        # @param [Boolean] dependency_collection Whether to send the `app-dependencies-loaded` event
        def initialize(
          heartbeat_interval_seconds:,
          metrics_aggregation_interval_seconds:,
          dependency_collection:,
          http_transport:,
          shutdown_timeout_seconds:,
          enabled: true,
          metrics_enabled: true,
          log_collection_enabled: true
        )
          @enabled = enabled
          @log_collection_enabled = log_collection_enabled

          @metrics_manager = MetricsManager.new(
            enabled: enabled && metrics_enabled,
            aggregation_interval: metrics_aggregation_interval_seconds
          )

          @worker = Telemetry::Worker.new(
            enabled: @enabled,
            heartbeat_interval_seconds: heartbeat_interval_seconds,
            metrics_aggregation_interval_seconds: metrics_aggregation_interval_seconds,
            emitter: Emitter.new(http_transport: http_transport),
            metrics_manager: @metrics_manager,
            dependency_collection: dependency_collection,
            shutdown_timeout: shutdown_timeout_seconds
          )

          @stopped = false

          @worker.start
        end

        def disable!
          @enabled = false
          @worker.enabled = false
        end

        def stop!
          return if @stopped

          @worker.stop(true)
          @stopped = true
        end

        def emit_closing!
          return if !@enabled || forked?

          @worker.enqueue(Event::AppClosing.new)
        end

        def integrations_change!
          return if !@enabled || forked?

          @worker.enqueue(Event::AppIntegrationsChange.new)
        end

        def log!(event)
          return if !@enabled || forked? || !@log_collection_enabled

          @worker.enqueue(event)
        end

        # Report configuration changes caused by Remote Configuration.
        def client_configuration_change!(changes)
          return if !@enabled || forked?

          @worker.enqueue(Event::AppClientConfigurationChange.new(changes, 'remote_config'))
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
      end
    end
  end
end
