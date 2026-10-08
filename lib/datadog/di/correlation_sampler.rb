# frozen_string_literal: true

require_relative "../core/rate_limiter"
require_relative "correlation_sampler/trace_budget"
require_relative "correlation_sampler/trace_budget_ledger"

module Datadog
  module DI
    # Sampling gate that coordinates capturing Live Debugger probe hits within
    # one trace and bounds total snapshot volume with process-wide budgets.
    #
    # @api private
    class CorrelationSampler
      # Upper bound on retained per-trace budgets.
      DEFAULT_MAX_ENTRIES = 4096

      # Snapshots per second, process-wide, that may establish an emitting
      # trace.
      TOP_RATE = 10

      # Snapshots per second, process-wide, across all emits.
      GLOBAL_RATE = 20

      # Snapshots one probe may emit within one trace.
      PER_PROBE_BUDGET = 1

      # Snapshots all probes together may emit within one trace.
      ALL_BUDGET = 20

      # Initializes an empty per-trace ledger and full process-wide TOP/GLOBAL
      # buckets.
      #
      # @param max_entries [Integer] bound for the per-trace budget ledger
      # @param top_rate [Numeric] TOP rate limit, snapshots/second
      # @param global_rate [Numeric] GLOBAL rate limit, snapshots/second
      # @param per_probe_budget [Integer] per-probe counter start value for
      #   each trace's budget
      # @param all_budget [Integer] all-probe counter start value for each
      #   trace's budget
      # @raise [ArgumentError] when max_entries is not a positive Integer, or
      #   per_probe_budget or all_budget is not a non-negative Integer
      def initialize(max_entries: DEFAULT_MAX_ENTRIES, top_rate: TOP_RATE,
        global_rate: GLOBAL_RATE, per_probe_budget: PER_PROBE_BUDGET,
        all_budget: ALL_BUDGET)
        unless max_entries.is_a?(Integer) && max_entries.positive?
          raise ArgumentError, "max_entries must be a positive Integer: #{max_entries}"
        end
        unless per_probe_budget.is_a?(Integer) && per_probe_budget >= 0
          raise ArgumentError, "per_probe_budget must be a non-negative Integer: #{per_probe_budget}"
        end
        unless all_budget.is_a?(Integer) && all_budget >= 0
          raise ArgumentError, "all_budget must be a non-negative Integer: #{all_budget}"
        end

        @per_probe_budget = per_probe_budget
        @all_budget = all_budget
        @lock = Mutex.new
        @trace_budgets = TraceBudgetLedger.new(max_entries)
        @top_limiter = Core::TokenBucket.new(top_rate)
        @global_limiter = Core::BorrowingTokenBucket.new(global_rate)

        nil # standard:disable Lint/Void
      end

      # Decides whether this capturing probe hit emits a snapshot.
      #
      # @param probe [Datadog::DI::Probe]
      # @param trace_id [Integer, nil]
      # @return [Boolean]
      def emit?(probe, trace_id)
        return emit_uncorrelated?(probe) if trace_id.nil?

        lock.synchronize do
          budget = touch_budget(trace_id)
          if budget
            emit_correlated?(budget, probe)
          else
            emit_top?(trace_id, probe)
          end
        end
      end

      private

      # Process-wide mutex guarding trace_budgets and the shared limiters; every
      # correlated capturing fire serializes here, a conscious trade-off for O(1)
      # critical sections.
      # @return [Thread::Mutex]
      attr_reader :lock

      # Bounded store of per-trace budgets.
      # @return [TraceBudgetLedger]
      attr_reader :trace_budgets

      # Process-wide TOP gate.
      # @return [Datadog::Core::TokenBucket]
      attr_reader :top_limiter

      # Process-wide GLOBAL gate.
      # @return [Datadog::Core::BorrowingTokenBucket]
      attr_reader :global_limiter

      # Per-probe counter start value this sampler seeds trace budgets with.
      # @return [Integer]
      attr_reader :per_probe_budget

      # All-probe counter start value this sampler seeds trace budgets with.
      # @return [Integer]
      attr_reader :all_budget

      # Decides a hit with no active trace through the probe's own rate limit,
      # so uncorrelated hits are decided independently of one another.
      #
      # @param probe [Datadog::DI::Probe]
      # @return [Boolean]
      def emit_uncorrelated?(probe)
        probe.own_rate_limit_allows?
      end

      # Refreshes the trace budget's LRU recency and returns the budget; nil
      # when the trace has no established unit yet. Must hold the lock.
      #
      # @param key [Integer]
      # @return [TraceBudget, nil]
      def touch_budget(key)
        trace_budgets.fetch(key)
      end

      # First capturing probe in the trace. Passes the process-wide GLOBAL and
      # TOP gates to emit and seed the trace counters; on either gate's refusal,
      # or when the seeded budget denies the top probe itself, marks the trace
      # starved so every correlated probe in it also drops without re-querying
      # the process-wide gates. Must hold the lock.
      #
      # @param key [Integer]
      # @param probe [Datadog::DI::Probe]
      # @return [Boolean]
      def emit_top?(key, probe)
        unless global_limiter.available? && top_limiter.allow?
          store(key, TraceBudget.new(per_probe_budget: per_probe_budget, all_budget: 0))
          return false
        end

        global_limiter.consume
        budget = TraceBudget.new(per_probe_budget: per_probe_budget, all_budget: all_budget)
        store(key, budget)
        budget.admit(probe.id)
      end

      # A capturing probe firing inside an established unit. Bounded by the
      # per-probe and all counters; consumes GLOBAL on emit. Must hold the lock.
      #
      # @param budget [TraceBudget]
      # @param probe [Datadog::DI::Probe]
      # @return [Boolean]
      def emit_correlated?(budget, probe)
        return false unless budget.admit(probe.id)

        global_limiter.consume
        true
      end

      # Stores the trace's budget in the ledger. Must hold the lock.
      #
      # @param key [Integer]
      # @param budget [TraceBudget]
      # @return [void]
      def store(key, budget)
        trace_budgets.store(key, budget)
      end
    end
  end
end
