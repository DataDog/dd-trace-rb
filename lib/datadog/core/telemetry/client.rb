# frozen_string_literal: true

require_relative 'emitter'
require_relative 'worker'
require_relative '../utils/forking'
require_relative 'metric'
require_relative 'metric_queue'

module Datadog
  module Core
    module Telemetry
      # Telemetry entrypoint, coordinates sending telemetry events at various points in app lifecycle.
      class Client
        attr_reader \
          :emitter,
          :enabled,
          :metrics_enabled,
          :unsupported,
          :worker,
          :metrics_worker

        include Core::Utils::Forking

        # @param enabled [Boolean] Determines whether telemetry events should be sent to the API
        # @param heartbeat_interval_seconds [Float] How frequently heartbeats will be reported, in seconds.
        def initialize(heartbeat_interval_seconds:, metrics_enabled:, enabled: true)
          @enabled = enabled
          @metrics_enabled = metrics_enabled
          @emitter = Emitter.new
          @stopped = false
          @unsupported = false
          @worker = Telemetry::Worker.new(
            enabled: @enabled || @metrics_enabled,
            heartbeat_interval_seconds: heartbeat_interval_seconds
          ) do
            heartbeat!
            flush_metrics!
          end

          Metric::Rate.interval = heartbeat_interval_seconds

          @metric_queue = MetricQueue.new
        end

        def disable!
          @enabled = false
          @metrics_enabled = false
          @worker.enabled = false
        end

        def started!
          return if !@enabled || forked?

          res = @emitter.request(:'app-started')

          if res.not_found? # Telemetry is only supported by agent versions 7.34 and up
            Datadog.logger.debug('Agent does not support telemetry; disabling future telemetry events.')
            disable!
            @unsupported = true # Prevent telemetry from getting re-enabled
          end

          res
        end

        def emit_closing!
          return if !@enabled || forked?

          @emitter.request(:'app-closing')
        end

        def stop!
          return if @stopped

          @worker.stop(true, 0)
          @stopped = true
        end

        def integrations_change!
          return if !@enabled || forked?

          @emitter.request(:'app-integrations-change')
        end

        # Report configuration changes caused by Remote Configuration.
        def client_configuration_change!(changes)
          return if !@enabled || forked?

          @emitter.request('app-client-configuration-change', data: { changes: changes, origin: 'remote_config' })
        end

        def add_count_metric(namespace, name, value, tags)
          return if !@metrics_enabled || forked?

          @metric_queue.add_metric(namespace, name, value, tags, Metric::Count)
        end

        def add_rate_metric(namespace, name, value, tags)
          return if !@metrics_enabled || forked?

          @metric_queue.add_metric(namespace, name, value, tags, Metric::Rate)
        end

        def add_gauge_metric(namespace, name, value, tags)
          return if !@metrics_enabled || forked?

          @metric_queue.add_metric(namespace, name, value, tags, Metric::Gauge)
        end

        def add_distribution_metric(namespace, name, value, tags)
          return if !@metrics_enabled || forked?

          @metric_queue.add_metric(namespace, name, value, tags, Metric::Distribution)
        end

        private

        def heartbeat!
          return if !@enabled || forked?

          @emitter.request(:'app-heartbeat')
        end

        def flush_metrics!
          return if !@metrics_enabled || forked?

          # We store the current metric_queue in a local variable and assign a new metric queue
          # so a paralallel thread can add metrics while we are still reporting the ones from
          # local_metric_queue
          local_metric_queue = @metric_queue
          @metric_queue = MetricQueue.new

          # Send metrics
          local_metric_queue.build_metrics_payload do |metric_type, payload|
            @emitter.request(metric_type, payload: payload)
          end
        end
      end
    end
  end
end
