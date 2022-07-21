# typed: true

require 'datadog/core/telemetry/emitter'
require 'datadog/core/telemetry/heartbeat'
require 'datadog/core/utils/forking'

module Datadog
  module Core
    module Telemetry
      # Telemetry entrypoint, coordinates sending telemetry events at various points in app lifecyle
      class Client
        attr_reader \
          :emitter,
          :enabled,
          :unsupported,
          :worker

        include Core::Utils::Forking

        # @param enabled [Boolean] Determines whether telemetry events should be sent to the API
        def initialize(enabled: true)
          @enabled = enabled
          @emitter = Emitter.new
          @stopped = false
          @unsupported = false
          @worker = Telemetry::Heartbeat.new(enabled: @enabled) do
            heartbeat!
          end
        end

        def reenable!
          unless @enabled || @unsupported
            @enabled = true
            @worker.enabled = true
          end
        end

        def disable!
          @enabled = false
          @worker.enabled = false
        end

        def started!
          return if !@enabled || self.class.started

          res = @emitter.request('app-started')

          if res.not_found? # Telemetry is only supported by agent versions 7.34 and up
            Datadog.logger.debug('Agent does not support telemetry; disabling future telemetry events.')
            @enabled = false
            @worker.enabled = false
            @unsupported = true # Prevent telemetry from getting re-enabled
          else
            self.class.started = true
          end

          res
        end

        def emit_closing!
          return if !@enabled || forked? # Only emit app-closing event in main process

          @emitter.request('app-closing')
        end

        def stop!
          return if @stopped

          @worker.stop(true, 0)
          @stopped = true
        end

        def integrations_change!
          return unless @enabled

          @emitter.request('app-integrations-change')
        end

        class << self
          attr_writer :started

          def started
            @started ||= false
          end
        end

        private

        def heartbeat!
          return unless @enabled

          @emitter.request('app-heartbeat')
        end
      end
    end
  end
end
