# frozen_string_literal: true

require "weakref"

require_relative "trace_budget_ledger/entry"

module Datadog
  module DI
    class CorrelationSampler
      # Store of per-trace budgets, keyed by the trace object and bound to its
      # lifetime: an entry dies with its trace, and a live trace keeps its
      # entry. Dead entries are dropped by a lazy sweep once the entry
      # count passes the sweep high-water mark.
      #
      # @api private
      class TraceBudgetLedger
        # Initializes the ledger with +sweep_threshold+ as the floor of the
        # sweep high-water mark.
        #
        # @param sweep_threshold [Integer] lower bound on the entry count that
        #   triggers a sweep of dead entries
        # @raise [ArgumentError] when sweep_threshold is not a positive Integer
        # @return [void]
        def initialize(sweep_threshold)
          unless sweep_threshold.is_a?(Integer) && sweep_threshold.positive?
            raise ArgumentError, "sweep_threshold must be a positive Integer: #{sweep_threshold}"
          end

          @sweep_threshold = sweep_threshold
          @entries = {}
          @live_count = 0
        end

        # Floor of the sweep high-water mark.
        #
        # @return [Integer]
        attr_reader :sweep_threshold

        # Retained budget entries keyed by trace object id.
        #
        # @return [Hash[Integer, Entry]]
        attr_reader :entries

        # Returns the budget stored for +trace+, or nil when the trace has no
        # stored budget. A dead weak reference is discarded as a miss.
        #
        # @param trace [Datadog::Tracing::TraceOperation] the active trace
        # @return [TraceBudget, nil]
        def fetch(trace)
          entry = entries[trace.object_id]
          return nil unless entry

          if entry.trace_ref.weakref_alive? && entry.trace_ref.__getobj__.equal?(trace)
            entry.budget
          else
            entries.delete(trace.object_id)
            nil
          end
        end

        # Stores +budget+ for +trace+.
        #
        # @param trace [Datadog::Tracing::TraceOperation] the active trace
        # @param budget [TraceBudget] the trace's budget
        # @return [void]
        def store(trace, budget)
          sweep if entries.size >= sweep_bound
          entries[trace.object_id] = Entry.new(trace_ref: WeakRef.new(trace), budget: budget)
          nil
        end

        private

        # Live entry count after the last sweep.
        #
        # @return [Integer]
        attr_reader :live_count

        # Entry count that triggers the next sweep: at least +sweep_threshold+,
        # and at least twice the live count, so an all-live store is swept once
        # per doubling.
        #
        # @return [Integer]
        def sweep_bound
          [sweep_threshold, live_count * 2].max
        end

        # Drops entries whose trace is gone.
        #
        # @return [void]
        def sweep
          entries.delete_if { |_id, entry| !entry.trace_ref.weakref_alive? }
          @live_count = entries.size
          nil
        end
      end
    end
  end
end
