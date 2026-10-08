# frozen_string_literal: true

module Datadog
  module DI
    class CorrelationSampler
      # Per-trace emission counters: one all counter shared by every probe,
      # and a per-probe counter that starts at +per_probe_budget+ for each
      # distinct probe.
      #
      # @api private
      class TraceBudget
        # Initializes the all-probe counter to +all_budget+ with each probe's
        # counter starting at +per_probe_budget+.
        #
        # @param per_probe_budget [Integer] per-probe counter start value
        # @param all_budget [Integer] all-probe counter start value
        # @raise [ArgumentError] when either budget is not a non-negative
        #   Integer
        def initialize(per_probe_budget:, all_budget:)
          unless per_probe_budget.is_a?(Integer) && per_probe_budget >= 0
            raise ArgumentError, "per_probe_budget must be a non-negative Integer: #{per_probe_budget}"
          end
          unless all_budget.is_a?(Integer) && all_budget >= 0
            raise ArgumentError, "all_budget must be a non-negative Integer: #{all_budget}"
          end

          @all_remaining = all_budget
          @per_probe_budget = per_probe_budget
          @per_probe = {}

          nil # standard:disable Lint/Void
        end

        # Remaining all-probe counter.
        #
        # @return [Integer]
        attr_reader :all_remaining

        # Per-probe counter start value this budget was constructed with.
        #
        # @return [Integer]
        attr_reader :per_probe_budget

        # Remaining per-probe counters, keyed by probe id.
        #
        # @return [Hash[String, Integer]]
        attr_reader :per_probe

        # Consumes one per-probe and one all token for +probe_id+.
        #
        # @return [Boolean] true when both counters had budget and were
        #   consumed, false when either was exhausted
        def admit(probe_id)
          remaining = per_probe.fetch(probe_id, per_probe_budget)
          return false if remaining <= 0 || all_remaining <= 0

          per_probe[probe_id] = remaining - 1
          @all_remaining = all_remaining - 1
          true
        end
      end
    end
  end
end
