# typed: true

require 'datadog/core/telemetry/emitter'
require 'datadog/core/utils/sequence'

module Datadog
  module Core
    module Telemetry
      # Telemetry entrypoint, coordinates sending telemetry events at various points in app lifecyle
      class Client
        def initialize(enabled: true, sequence: Datadog::Core::Utils::Sequence.new(1))
          @enabled = enabled
          @emitter = Emitter.new(sequence: sequence)
        end

        def disable!
          @enabled = false
        end

        def started!
          return unless @enabled

          @emitter.request('app-started')
        end
      end
    end
  end
end
