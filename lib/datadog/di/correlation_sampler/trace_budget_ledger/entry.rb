# frozen_string_literal: true

module Datadog
  module DI
    class CorrelationSampler
      class TraceBudgetLedger
        # One retained budget and the weak reference to its trace.
        #
        # @api private
        class Entry
          # Weak reference to the trace the budget belongs to.
          #
          # @return [WeakRef]
          attr_reader :trace_ref

          # The trace's budget.
          #
          # @return [TraceBudget]
          attr_reader :budget

          # Initializes the entry.
          #
          # @param trace_ref [WeakRef] weak reference to the entry's trace
          # @param budget [TraceBudget] the trace's budget
          # @return [void]
          def initialize(trace_ref:, budget:)
            @trace_ref = trace_ref
            @budget = budget
          end
        end
      end
    end
  end
end
