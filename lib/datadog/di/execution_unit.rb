# frozen_string_literal: true

module Datadog
  module DI
    # Owns the execution unit that groups related Live Debugger probe hits: the
    # active APM trace, or the individual hit when no trace is active.
    #
    # The unit is resolved from existing tracer context only (the active trace
    # and span). No new context mechanism is introduced; when no trace is
    # active the hit is not correlated.
    #
    # @api private
    class ExecutionUnit
      # Resolves the unit enclosing the current probe hit.
      #
      # @return [ExecutionUnit]
      def self.current
        if defined?(Datadog::Tracing)
          trace = Datadog::Tracing.active_trace
          if trace && (trace_id = trace.id)
            span = Datadog::Tracing.active_span
            return new(trace_id, span&.id || trace_id, :apm)
          end
        end

        new(nil, nil, :none)
      end

      # Holds one resolved unit; callers obtain instances from {.current}.
      #
      # @param key [String, Integer, nil] groups hits that share one decision
      # @param scope [String, Integer, nil] bounds a probe's repeat emissions
      # @param source [Symbol] :apm or :none
      def initialize(key, scope, source)
        @key = key
        @scope = scope
        @source = source
      end

      # Identifies the unit whose hits share one emit-or-drop decision.
      attr_reader :key

      # Bounds how often a single probe emits inside the unit.
      attr_reader :scope

      # Origin of the unit: :apm or :none.
      attr_reader :source
    end
  end
end
