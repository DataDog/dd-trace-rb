# frozen_string_literal: true

require_relative "../core/rate_limiter"

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

      # Snapshots one probe may emit within one trace. The mechanism supports
      # a higher limit; the value is set to 1 so each probe contributes at most
      # one snapshot per trace.
      PER_PROBE_BUDGET = 1

      # Snapshots all probes together may emit within one trace.
      ALL_BUDGET = 20

      # The coordinated-sampling model (process-wide TOP/GLOBAL token buckets,
      # per-trace per-probe and all counters, and the borrowing global bucket)
      # follows the cross-tracer RFC "Improvements to Casual Correlation for
      # Live Debugger Snapshots". Tracers predating the RFC, such as
      # dd-trace-java, budget only per-probe-per-trace with no process-wide
      # gates; the Ruby implementation follows the RFC, so the divergence is
      # intentional. PER_PROBE_BUDGET is 1, below the RFC's higher target, to
      # satisfy the system-tests correlation gate (DataDog/system-tests#7425).

      # @param max_entries [Integer] bound for the per-trace budget ledger
      # @param top_rate [Numeric] TOP rate limit, snapshots/second
      # @param global_rate [Numeric] GLOBAL rate limit, snapshots/second
      # @param per_probe_budget [Integer] per-probe per-trace emission counter
      # @param all_budget [Integer] all-probe per-trace emission counter
      def initialize(max_entries: DEFAULT_MAX_ENTRIES, top_rate: TOP_RATE,
        global_rate: GLOBAL_RATE, per_probe_budget: PER_PROBE_BUDGET,
        all_budget: ALL_BUDGET)
        @max_entries = max_entries
        @per_probe_budget = per_probe_budget
        @all_budget = all_budget
        @lock = Mutex.new
        @trace_budgets = {}
        @top_limiter = Core::TokenBucket.new(top_rate)
        @global_limiter = Core::BorrowingTokenBucket.new(global_rate)
      end

      # Decides whether this capturing probe hit emits a snapshot.
      #
      # @param probe [Datadog::DI::Probe]
      # @param sampling_unit [Datadog::DI::SamplingUnit]
      # @return [Boolean]
      def emit?(probe, sampling_unit)
        key = sampling_unit.key
        return emit_uncorrelated?(probe) if key.nil?

        lock.synchronize do
          budget = fetch_budget(key)
          if budget
            emit_correlated?(budget, probe)
          else
            emit_top?(key, probe)
          end
        end
      end

      private

      # Process-wide mutex guarding trace_budgets and the shared limiters; every
      # correlated capturing fire serializes here, a conscious trade-off for O(1)
      # critical sections.
      attr_reader :lock

      # Per-trace budgets keyed by trace id, in LRU insertion order.
      attr_reader :trace_budgets

      # Process-wide TOP gate limiting how many traces per second may start emitting.
      attr_reader :top_limiter

      # Process-wide GLOBAL gate bounding total snapshots per second across all emits.
      attr_reader :global_limiter

      # Upper bound on retained per-trace budgets before LRU eviction.
      attr_reader :max_entries

      # Per-probe per-trace emission counter this sampler was constructed with.
      attr_reader :per_probe_budget

      # All-probe per-trace emission counter this sampler was constructed with.
      attr_reader :all_budget

      # Consults the probe's own rate limiter for a hit with no active trace,
      # consuming a token; a probe with no limiter is permitted.
      #
      # @param probe [Datadog::DI::Probe]
      # @return [Boolean]
      def emit_uncorrelated?(probe)
        limiter = probe.rate_limiter
        limiter.nil? || limiter.allow?
      end

      # Returns the trace's budget, refreshing its LRU recency; nil when the
      # trace has no established unit yet. Must hold the lock.
      #
      # @param key [Integer]
      # @return [TraceBudget, nil]
      def fetch_budget(key)
        budget = trace_budgets.delete(key)
        trace_budgets[key] = budget if budget
        budget
      end

      # First capturing probe in the trace. Passes the process-wide GLOBAL and
      # TOP gates to emit and seed the trace counters; on either gate's refusal,
      # marks the trace starved so every correlated probe in it also drops.
      # Must hold the lock.
      #
      # @param key [Integer]
      # @param probe [Datadog::DI::Probe]
      # @return [Boolean]
      def emit_top?(key, probe)
        unless global_limiter.available? && top_limiter.allow?
          # Store a starved budget so correlated probes in this trace drop
          # without re-querying the process-wide gates. The slot is reclaimed
          # by LRU eviction; at DEFAULT_MAX_ENTRIES the ledger bounds how many
          # starved traces occupy live slots.
          store(key, TraceBudget.new(per_probe_budget: per_probe_budget, all_budget: 0))
          return false
        end

        global_limiter.consume
        budget = TraceBudget.new(per_probe_budget: per_probe_budget, all_budget: all_budget)
        budget.admit(probe.id)
        store(key, budget)
        true
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

      # Stores the trace's budget, evicting the oldest trace when the ledger
      # exceeds the bound. Must hold the lock.
      #
      # @param key [Integer]
      # @param budget [TraceBudget]
      # @return [void]
      def store(key, budget)
        trace_budgets[key] = budget
        trace_budgets.shift if trace_budgets.size > max_entries
        nil
      end

      # Per-trace emission counters: one all counter shared by every probe, and
      # a per-probe counter that starts at +per_probe_budget+ for each distinct
      # probe.
      #
      # @api private
      class TraceBudget
        # @param per_probe_budget [Integer] per-probe counter start value
        # @param all_budget [Integer] all-probe counter start value
        def initialize(per_probe_budget:, all_budget:)
          @all_remaining = all_budget
          @per_probe_budget = per_probe_budget
          @per_probe = {}
        end

        # Remaining all-probe counter.
        attr_reader :all_remaining

        # Consumes one per-probe and one all token for +probe_id+.
        #
        # @param probe_id [String]
        # @return [Boolean] true when both counters had budget and were
        #   consumed, false when either was exhausted
        def admit(probe_id)
          remaining = @per_probe.fetch(probe_id, @per_probe_budget)
          return false if remaining <= 0 || all_remaining <= 0

          @per_probe[probe_id] = remaining - 1
          @all_remaining -= 1
          true
        end
      end
    end
  end
end
