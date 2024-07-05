# frozen_string_literal: true

require_relative 'emitter'
require_relative 'event'
require_relative 'worker'
require_relative '../utils/forking'

module Datadog
  module Core
    module Telemetry
      # Telemetry entrypoint, coordinates sending telemetry events at various points in app lifecycle.
      class Component
        attr_reader :enabled

        include Core::Utils::Forking

        # @param enabled [Boolean] Determines whether telemetry events should be sent to the API
        # @param metrics_enabled [Boolean] Determines whether telemetry metrics should be sent to the API
        # @param heartbeat_interval_seconds [Float] How frequently heartbeats will be reported, in seconds.
        # @param metrics_aggregation_interval_seconds [Float] How frequently metrics will be aggregated, in seconds.
        # @param [Boolean] dependency_collection Whether to send the `app-dependencies-loaded` event
        def initialize(
          heartbeat_interval_seconds:,
          metrics_aggregation_interval_seconds:,
          dependency_collection:, enabled: true,
          metrics_enabled: true
        )
          @enabled = enabled
          @stopped = false

          @worker = Telemetry::Worker.new(
            enabled: @enabled,
            heartbeat_interval_seconds: heartbeat_interval_seconds,
            metrics_aggregation_interval_seconds: metrics_aggregation_interval_seconds,
            emitter: Emitter.new,
            dependency_collection: dependency_collection
          )
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

        # Report configuration changes caused by Remote Configuration.
        def client_configuration_change!(changes)
          return if !@enabled || forked?

          @worker.enqueue(Event::AppClientConfigurationChange.new(changes, 'remote_config'))
        end
      end
    end
  end
end
