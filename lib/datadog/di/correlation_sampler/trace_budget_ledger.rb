# frozen_string_literal: true

module Datadog
  module DI
    class CorrelationSampler
      # Bounded store of per-trace budgets. Discard policy: when an entry is
      # stored beyond +max_entries+, the least recently used entry (insertion
      # order, recency refreshed on lookup) is evicted.
      #
      # @api private
      class TraceBudgetLedger
        # Initializes the ledger with +max_entries+ as its retention bound.
        #
        # @param max_entries [Integer] upper bound on retained entries
        def initialize(max_entries)
          @max_entries = max_entries
          @entries = {}

          nil # standard:disable Lint/Void
        end

        # Upper bound on retained entries.
        #
        # @return [Integer]
        attr_reader :max_entries

        # Retained trace budgets keyed by trace id, least recently used first.
        #
        # @return [Hash[Integer, TraceBudget]]
        attr_reader :entries

        # Returns the budget stored for +key+, refreshing its LRU recency, or
        # nil when the trace has no stored budget.
        #
        # @param key [Integer] trace id
        # @return [TraceBudget, nil]
        def fetch(key)
          entry = entries.delete(key)
          entries[key] = entry if entry

          entry
        end

        # Stores +entry+ for +key+, evicting the least recently used entry
        # once the store exceeds its bound.
        #
        # @param key [Integer] trace id
        # @param entry [TraceBudget] the trace's budget
        # @return [void]
        def store(key, entry)
          entries[key] = entry
          entries.shift if entries.size > max_entries
          nil
        end
      end
    end
  end
end
