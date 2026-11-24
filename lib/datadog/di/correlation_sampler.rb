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
      # Sweep floor for the per-trace budget ledger.
      DEFAULT_SWEEP_THRESHOLD = 4096

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
      # @param sweep_threshold [Integer] sweep floor for the per-trace budget
      #   ledger
      # @param top_rate [Numeric] TOP rate limit, snapshots/second
      # @param global_rate [Numeric] GLOBAL rate limit, snapshots/second
      # @param per_probe_budget [Integer] per-probe counter start value for
      #   each trace's budget
      # @param all_budget [Integer] all-probe counter start value for each
      #   trace's budget
      # @raise [ArgumentError] when sweep_threshold is zero, negative, or
      #   non-Integer, or when per_probe_budget or all_budget is negative
      #   or non-Integer
      # @return [void]
      def initialize(sweep_threshold: DEFAULT_SWEEP_THRESHOLD, top_rate: TOP_RATE,
        global_rate: GLOBAL_RATE, per_probe_budget: PER_PROBE_BUDGET,
        all_budget: ALL_BUDGET)
        TraceBudget.validate_budgets!(per_probe_budget: per_probe_budget, all_budget: all_budget)

        @per_probe_budget = per_probe_budget
        @all_budget = all_budget
        @sweep_threshold = sweep_threshold
        @top_rate = top_rate
        @global_rate = global_rate
        rebuild_state
      end

      # Decides whether this capturing probe hit emits a snapshot, and names
      # the drop decision for a denial.
      #
      # @param probe [Datadog::DI::Probe]
      # @param trace [Datadog::Tracing::TraceOperation, nil]
      # @return [Array(Boolean, Symbol, nil)] the admitted flag, and the drop
      #   decision naming the denying limit: +:own_rate_limit+,
      #   +:global_budget+, +:top_gate+ or +:trace_budget+, nil when admitted
      def emit_with_reason?(probe, trace)
        lock.synchronize do
          return emit_uncorrelated?(probe) if trace.nil?

          budget = trace_budgets.fetch(trace)
          if budget
            emit_correlated?(budget, probe)
          else
            emit_first_probe?(probe, trace)
          end
        end
      end

      # Decides whether this capturing probe hit emits a snapshot.
      #
      # @param probe [Datadog::DI::Probe]
      # @param trace [Datadog::Tracing::TraceOperation, nil]
      # @return [Boolean]
      def emit?(probe, trace)
        admitted, = emit_with_reason?(probe, trace)
        admitted
      end

      # Consumes one GLOBAL token for a snapshot payload the coordinated
      # emit path does not gate, such as a condition-evaluation-failure
      # notification with no active trace or from a non-capturing probe.
      # GLOBAL admits the payload only while the balance is
      # positive, matching the uncorrelated emit path, so condition-error
      # payloads and capturing emits share one process-wide snapshot budget.
      #
      # @return [Boolean] true when the process-wide budget admits the payload
      def admit_process_wide_snapshot?
        lock.synchronize do
          global_limiter.try_consume
        end
      end

      # Rebuilds the process-scoped state for a freshly forked child. Must
      # run while the child is single-threaded.
      #
      # @return [void]
      def after_fork!
        rebuild_state
        nil
      end

      private

      # Process-wide mutex guarding trace_budgets and the shared limiters.
      # @return [Thread::Mutex]
      attr_reader :lock

      # Store of per-trace budgets, keyed by the trace object.
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

      # Sweep floor this sampler rebuilds the ledger with.
      # @return [Integer]
      attr_reader :sweep_threshold

      # TOP rate this sampler rebuilds its TOP bucket with.
      # @return [Numeric]
      attr_reader :top_rate

      # GLOBAL rate this sampler rebuilds its GLOBAL bucket with.
      # @return [Numeric]
      attr_reader :global_rate

      # Builds the process-scoped state objects: the mutex, the per-trace
      # budget ledger and the TOP/GLOBAL buckets at the configured rates.
      #
      # @return [void]
      def rebuild_state
        @lock = Mutex.new
        @trace_budgets = TraceBudgetLedger.new(sweep_threshold)
        @top_limiter = Core::TokenBucket.new(top_rate)
        @global_limiter = Core::BorrowingTokenBucket.new(global_rate)
        nil
      end

      # Decides a hit with no active trace through the probe's own rate
      # limit and the process-wide GLOBAL budget. Must hold the lock.
      #
      # @param probe [Datadog::DI::Probe]
      # @return [Array(Boolean, Symbol, nil)] the admitted flag and the drop
      #   decision, nil when admitted
      def emit_uncorrelated?(probe)
        return [false, :own_rate_limit] unless probe.own_rate_limit_allows?
        return [false, :global_budget] unless global_limiter.try_consume

        [true, nil]
      end

      # First capturing probe in the trace. Passes the process-wide GLOBAL and
      # TOP gates to emit and seed the trace counters; on either gate's refusal,
      # or when the seeded budget denies the top probe itself, marks the trace
      # starved so every correlated probe in it also drops without re-querying
      # the process-wide gates. The GLOBAL gate consumes its token as part of
      # the check, so a hit the TOP gate refuses still spends one GLOBAL
      # token, and GLOBAL refills once per hit. Must hold the lock.
      #
      # @param probe [Datadog::DI::Probe]
      # @param trace [Datadog::Tracing::TraceOperation]
      # @return [Array(Boolean, Symbol, nil)] the admitted flag and the drop
      #   decision, nil when admitted
      def emit_first_probe?(probe, trace)
        unless global_limiter.try_consume && top_limiter.allow?
          store(trace, TraceBudget.new(per_probe_budget: per_probe_budget, all_budget: 0))
          return [false, :top_gate]
        end

        budget = TraceBudget.new(per_probe_budget: per_probe_budget, all_budget: all_budget)
        store(trace, budget)
        return [false, :trace_budget] unless budget.admit(probe.id)

        [true, nil]
      end

      # A capturing probe firing inside an established unit. Bounded by the
      # per-probe and all counters; consumes GLOBAL on emit. Must hold the lock.
      #
      # @param budget [TraceBudget]
      # @param probe [Datadog::DI::Probe]
      # @return [Array(Boolean, Symbol, nil)] the admitted flag and the drop
      #   decision, nil when admitted
      def emit_correlated?(budget, probe)
        return [false, :trace_budget] unless budget.admit(probe.id)

        global_limiter.consume
        [true, nil]
      end

      # Stores the trace's budget in the ledger. Must hold the lock.
      #
      # @param trace [Datadog::Tracing::TraceOperation]
      # @param budget [TraceBudget]
      # @return [void]
      def store(trace, budget)
        trace_budgets.store(trace, budget)
      end
    end
  end
end
