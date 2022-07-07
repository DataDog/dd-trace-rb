# typed: true

require 'datadog/core/telemetry/emitter'
require 'datadog/core/telemetry/heartbeat'
require 'datadog/core/utils/sequence'

module Datadog
  module Core
    module Telemetry
      # Telemetry entrypoint, coordinates sending telemetry events at various points in app lifecyle
      class Client
        attr_reader \
          :enabled,
          :emitter,
          :worker

        # @param enabled [Boolean] Determines whether telemetry events should be sent to the API
        # @param sequence [Datadog::Core::Utils::Sequence] Sequence object that stores and increments a counter
        def initialize(enabled: true, sequence: Datadog::Core::Utils::Sequence.new(1))
          @enabled = enabled
          @emitter = Emitter.new(sequence: sequence)
          started!
          @worker = Telemetry::Heartbeat.new(enabled: @enabled) do
            heartbeat!
          end
          @stopped = false
        end

        def reenable!
          unless @enabled
            @enabled = true
            @worker.enabled = true
          end
        end

        def disable!
          @enabled = false
          @worker.enabled = false
        end

        def started!
          return unless @enabled

          @emitter.request('app-started')
        end

        def stop!
          return if @stopped

          @worker.stop
          @worker.join
          @stopped = true

          return unless @enabled

          @emitter.request('app-closing')
        end

        def integrations_change!
          return unless @enabled

          @emitter.request('app-integrations-change')
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
