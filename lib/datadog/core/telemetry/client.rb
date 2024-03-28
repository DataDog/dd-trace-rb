# frozen_string_literal: true

require_relative 'emitter'
require_relative 'event'
require_relative 'heartbeat'
require_relative '../utils/forking'

module Datadog
  module Core
    module Telemetry
      # Telemetry entrypoint, coordinates sending telemetry events at various points in app lifecycle.
      class Client
        attr_reader \
          :enabled,
          :unsupported

        include Core::Utils::Forking

        # @param enabled [Boolean] Determines whether telemetry events should be sent to the API
        # @param heartbeat_interval_seconds [Float] How frequently heartbeats will be reported, in seconds.
        # @param [Boolean] dependency_collection Whether to send the `app-dependencies-loaded` event
        def initialize(heartbeat_interval_seconds:, dependency_collection:, enabled: true)
          @enabled = enabled
          @emitter = Emitter.new
          @stopped = false
          @unsupported = false
          @started = false
          @dependency_collection = dependency_collection

          @worker = Telemetry::Heartbeat.new(enabled: @enabled, heartbeat_interval_seconds: heartbeat_interval_seconds) do
            next unless @started # `started!` should be the first event, thus ensure that `heartbeat!` is not sent first.

            heartbeat!
          end
        end

        def disable!
          @enabled = false
          @worker.enabled = false
        end

        def started!
          return if !@enabled || forked?

          res = @emitter.request(Event::AppStarted.new)

          if res.not_found? # Telemetry is only supported by agent versions 7.34 and up
            Datadog.logger.debug('Agent does not support telemetry; disabling future telemetry events.')
            disable!
            @unsupported = true # Prevent telemetry from getting re-enabled
            return res
          end

          @emitter.request(Event::AppDependenciesLoaded.new) if @dependency_collection

          @started = true
        end

        def emit_closing!
          return if !@enabled || forked?

          @emitter.request(Event::AppClosing.new)
        end

        def stop!
          return if @stopped

          @worker.stop(true, 0)
          @stopped = true
        end

        def integrations_change!
          return if !@enabled || forked?

          @emitter.request(Event::AppIntegrationsChange.new)
        end

        # Report configuration changes caused by Remote Configuration.
        def client_configuration_change!(changes)
          return if !@enabled || forked?

          @emitter.request(Event::AppClientConfigurationChange.new(changes, 'remote_config'))
        end

        private

        def heartbeat!
          return if !@enabled || forked?

          @emitter.request(Event::AppHeartbeat.new)
        end
      end
    end
  end
end
