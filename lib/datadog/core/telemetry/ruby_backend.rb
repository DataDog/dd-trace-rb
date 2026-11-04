# frozen_string_literal: true

require_relative "emitter"
require_relative "metrics_manager"
require_relative "worker"
require_relative "transport/http"

require_relative "../configuration/agentless_settings_resolver"

module Datadog
  module Core
    module Telemetry
      # Ruby telemetry backend: the metrics manager, the event worker, and
      # the HTTP transport, unchanged from before the backend seam existed.
      # The component selects between this and a native backend.
      #
      # @api private
      class RubyBackend
        attr_reader :metrics_manager
        attr_reader :transport
        attr_reader :worker

        def initialize( # standard:disable Metrics/MethodLength
          settings:,
          agent_settings:,
          logger:,
          enabled:
        )
          @enabled = enabled
          @logger = logger

          @metrics_manager = MetricsManager.new(
            enabled: enabled && settings.telemetry.metrics_enabled,
            aggregation_interval: settings.telemetry.metrics_aggregation_interval_seconds,
          )

          return unless enabled

          @transport = if settings.telemetry.agentless_enabled
            # We do not touch the `agent_settings` since we still want the telemetry payloads to refer to the original
            # settings, even though the telemetry itself may be using a different path.
            telemetry_specific_agent_settings = Core::Configuration::AgentlessSettingsResolver.call(
              settings,
              host_prefix: "instrumentation-telemetry-intake",
              url_override: settings.telemetry.agentless_url_override,
              url_override_source: "c.telemetry.agentless_url_override",
              logger: logger,
            )
            Telemetry::Transport::HTTP.agentless_telemetry(
              agent_settings: telemetry_specific_agent_settings,
              logger: logger,
              # api_key has already been validated to be
              # not nil by +Component.build+.
              api_key: settings.api_key,
            )
          else
            Telemetry::Transport::HTTP.agent_telemetry(
              agent_settings: agent_settings, logger: logger,
            )
          end

          @worker = Telemetry::Worker.new(
            enabled: enabled,
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
            settings: settings,
            agent_settings: agent_settings,
            shutdown_timeout: settings.telemetry.shutdown_timeout_seconds,
          )
        end

        def disable!
          @worker&.enabled = false
        end

        def start(initial_event)
          @worker.start(initial_event)
        end

        # Returns true if event was enqueued, nil if not.
        def enqueue(event)
          @worker.enqueue(event)
        end

        def flush(timeout: nil)
          @worker.flush(timeout: timeout)
        end

        def inc(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.inc(namespace, metric_name, value, tags: tags, common: common)
        end

        def dec(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.dec(namespace, metric_name, value, tags: tags, common: common)
        end

        def gauge(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.gauge(namespace, metric_name, value, tags: tags, common: common)
        end

        def rate(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.rate(namespace, metric_name, value, tags: tags, common: common)
        end

        def distribution(namespace, metric_name, value, tags: {}, common: true)
          @metrics_manager.distribution(namespace, metric_name, value, tags: tags, common: common)
        end

        # When a fork happens, we need to do two things inside the
        # child process:
        # 1. Restart the worker.
        # 2. Discard any events and metrics that were submitted in the
        #    parent process. The parent sends them out itself, so the
        #    child must not send them again.
        def after_fork
          # We cannot create a new metrics manager instance because other
          # objects reference it (for example, the worker).
          # We must reset the existing instance.
          @metrics_manager.clear

          worker&.send(:after_fork_monkey_patched)
        end

        def shutdown!
          return if @stopped

          if defined?(@worker)
            @worker&.stop(true)
          end

          @stopped = true
        end
      end
    end
  end
end
