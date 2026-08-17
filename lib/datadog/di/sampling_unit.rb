# frozen_string_literal: true

module Datadog
  module DI
    # Identifies the correlation unit that groups related Live Debugger probe
    # hits: the active APM trace. The unit is resolved from existing tracer
    # context only (an in-process read of the active trace). When no trace is
    # active the hit belongs to no unit and is not correlated.
    #
    # @api private
    class SamplingUnit
      # Resolves the unit enclosing the current probe hit.
      #
      # @return [SamplingUnit]
      def self.current
        if defined?(Datadog::Tracing)
          trace = Datadog::Tracing.active_trace
          if trace && (trace_id = trace.id)
            return new(trace_id)
          end
        end

        NONE
      end

      # @param key [String, Integer, nil] the trace id, or nil when no trace is
      #   active
      def initialize(key)
        @key = key
      end

      # Groups hits that share one emit-or-drop decision; nil when no trace is
      # active.
      attr_reader :key

      NONE = new(nil)
    end
  end
end
