# frozen_string_literal: true

module Datadog
  module DI
    # Correlation unit that groups related Live Debugger probe hits by their
    # active APM trace. Resolved from existing tracer context only (an
    # in-process read of the active trace); when no trace is active the hit
    # belongs to no unit and is not correlated.
    #
    # @api private
    class SamplingUnit
      # Resolves the unit enclosing the current probe hit.
      #
      # @return [SamplingUnit]
      def self.current
        # Checked per call, not hoisted to load time: DI may be required before
        # Datadog::Tracing, so this constant can transition from undefined
        # to defined after boot. Called on every capturing probe firing; the single
        # SamplingUnit allocation per fire is accepted to keep the correlation
        # unit an explicit object.
        if defined?(Datadog::Tracing)
          trace = Datadog::Tracing.active_trace
          if trace && (trace_id = trace.id)
            return new(trace_id)
          end
        end

        NONE
      end

      # @param key [Integer, nil] the trace id, or nil when no trace is active
      def initialize(key)
        @key = key
      end

      # Trace id shared by hits in this unit; nil when no trace is active.
      attr_reader :key

      # Sentinel unit for a hit with no active trace; shared by all
      # uncorrelated hits.
      NONE = new(nil)
    end
  end
end
