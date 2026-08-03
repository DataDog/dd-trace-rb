# frozen_string_literal: true

require_relative "ext"
require_relative "rate_sampler"

module Datadog
  module Tracing
    module Sampling
      # OpenTelemetry consistent probability sampling (OTEP 235).
      #
      # Re-expresses Datadog's Knuth-hash sampling decision as the OTel `(rv, th)` pair
      # carried in the `ot=` member of the W3C `tracestate` header:
      #
      #   * `rv` (random value): 56-bit explicit randomness, the inverted+truncated Knuth
      #     hash of the trace id. A trace is kept when `rv >= th`.
      #   * `th` (rejection threshold): 56-bit, derived from the applied sample rate as
      #     `round((1 - rate) * 2^56)`.
      #
      # This module holds the shared math so a given trace id / rate always yields
      # identical values, matching the cross-language reference. The `ot=` member is
      # (de)serialized alongside `dd=` in {Datadog::Tracing::Distributed::TraceContext}.
      #
      # @api private
      # @see https://opentelemetry.io/docs/specs/otel/trace/tracestate-probability-sampling/
      module OtelConsistentSampling
        # 2^56, the range of both `rv` and `th`.
        MAX_THRESHOLD = 1 << 56

        # Largest emittable threshold. `th == MAX_THRESHOLD` would mean "never sample",
        # which is not expressible as a probability, so we clamp to one below.
        MAX_ENCODABLE_THRESHOLD = MAX_THRESHOLD - 1

        UINT64_MODULO = 1 << 64
        UINT64_MASK = UINT64_MODULO - 1

        # A well-formed threshold is 1 to 14 lowercase hex digits (a 56-bit value, trailing
        # zero nibbles trimmed).
        VALID_THRESHOLD = /\A[0-9a-f]{1,14}\z/

        # A well-formed random value is exactly 14 lowercase hex digits (a zero-padded 56-bit
        # value).
        VALID_RANDOM_VALUE = /\A[0-9a-f]{14}\z/

        # Decision makers that are NOT probability decisions: when one of these is the
        # effective decision maker, the trace was force-kept and no threshold applies.
        NON_PROBABILITY_DECISIONS = [
          Ext::Decision::MANUAL,
          Ext::Decision::ASM,
          Ext::Decision::AI_GUARD,
        ].freeze

        module_function

        # Resolves the wire values (`rv`, `th`) to emit given the local sampling decision.
        #
        # The values are returned already formatted for the `ot=` tracestate member, so
        # inbound values are forwarded byte-for-byte and only DD-generated values are
        # newly formatted.
        #
        # @param trace_id [Integer]
        # @param sampling_priority [Integer, nil]
        # @param decision_maker [String, nil] the effective `_dd.p.dm` value
        # @param applied_rate [Float, nil] `rule_sample_rate || agent_sample_rate`
        # @param rate_limiter_rate [Float, nil] set only when a rule kept-by-probability
        # @param inbound_random_value [String, nil] head-set randomness to preserve
        # @param inbound_threshold [String, nil] threshold decided upstream
        # @param distributed_sampling_priority [Boolean] whether a sampling priority was
        #   already assigned to this trace from an upstream distributed context, i.e. a
        #   decision was already made and should be preserved rather than re-decided
        # @return [Array(String?, String?)] `[random_value, threshold]` hex strings to emit
        def resolve_outbound(
          trace_id:,
          sampling_priority:,
          decision_maker:,
          applied_rate:,
          rate_limiter_rate:,
          inbound_random_value:,
          inbound_threshold:,
          distributed_sampling_priority:
        )
          # A non-probability force-keep (manual, ASM, AI Guard) is not a probability
          # decision, so erase the threshold: leaving `th` would let a downstream collector
          # or participant re-run a probability decision and drop the trace we deliberately
          # force-kept. The random value is the trace's explicit randomness (not a decision),
          # so keep it for consistent per-hop sampling downstream.
          return [inbound_random_value, nil] if NON_PROBABILITY_DECISIONS.include?(decision_maker)

          trace_kept = sampling_priority && sampling_priority >= Ext::Priority::AUTO_KEEP
          # The rate limiter rate is always set on the trace when the trace is sampled
          # by a probabilistic rule, which means that if there is the rate limiter rate,
          # the trace should be kept EXCEPT if the rate limiter dropped the trace.
          limiter_dropped = rate_limiter_rate && !trace_kept

          # Rate-limiter drop: no threshold. Keep an inherited random
          # value so downstream per-hop sampling stays consistent.
          return [inbound_random_value, nil] if limiter_dropped

          # Decided upstream: forward the threshold (and/or any explicit random value)
          # unchanged, do not re-decide. When it arrives without a random value or threshold, leave it
          # absent — downstream participants fall back to the W3C implicit random value
          # (the trace id's 56 least-significant bits) themselves.
          return [inbound_random_value, inbound_threshold] if inbound_threshold || inbound_random_value

          # Only a trace that is making its own probability decision may derive a fresh
          # `(rv, th)`. When a sampling priority was already assigned upstream (e.g. an
          # older OpenTelemetry or Datadog SDK that sent no `ot` fields), DD is following
          # that decision, not making its own, so fabricating values here would advertise a
          # decision the origin never made: emit nothing. Same if no rate is applied.
          return [nil, nil] if distributed_sampling_priority || !applied_rate

          th = threshold(applied_rate)
          # Datadog is deriving the random value: reconcile the 64-bit keep/drop decision
          # with the 56-bit threshold so a downstream participant agrees.
          rv = reconcile_random_value(random_value(trace_id), th, !!trace_kept)
          [format_random_value(rv), format_threshold(th)]
        end

        # Parses the value of an `ot=` tracestate member (the part after `ot=`).
        #
        # `rv`/`th` are kept as their raw hex strings so they are forwarded byte-for-byte;
        # other sub-keys are preserved (with a trailing `;`) for pass-through.
        #
        # Malformed `rv`/`th` are each ignored independently
        #
        # @param value [String] the `ot=` member value
        # @return [Hash] `{random_value:, threshold:, unknown_fields:}`, each value may be nil
        def extract_otel_fields(value)
          # @type var random_value: ::String?
          # @type var threshold: ::String?
          # @type var unknown: ::Array[::String]
          random_value = nil
          threshold = nil
          unknown = []

          value.split(";").each do |pair|
            key, field = pair.split(":", 2)
            case key
            when "rv"
              random_value = field
            when "th"
              threshold = field
            else
              unknown << pair
            end
          end

          threshold = nil if threshold && !VALID_THRESHOLD.match?(threshold)
          random_value = nil if random_value && !VALID_RANDOM_VALUE.match?(random_value)

          {
            random_value: random_value,
            threshold: threshold,
            unknown_fields: unknown.empty? ? nil : "#{unknown.join(";")};",
          }
        end

        # Derives the 56-bit OTel random value from a Datadog trace id.
        #
        # `h` is the Knuth multiplicative hash (the same one used to make the keep/drop
        # decision). Inverting every bit reverses the comparison direction (DD keeps low
        # `h`, OTel keeps high `rv`); the right shift keeps the top 56 bits so ordering is
        # preserved.
        #
        # @param trace_id [Integer] the (up to 128-bit) trace id
        # @return [Integer] a 56-bit random value
        def random_value(trace_id)
          h = (trace_id * RateSampler::KNUTH_FACTOR) % UINT64_MODULO
          (~h & UINT64_MASK) >> 8
        end

        # Converts an applied sample rate into a 56-bit rejection threshold.
        #
        # Uses round-to-nearest (ties away from zero) at full 56-bit precision, matching
        # the cross-language reference so a given rate yields an identical threshold.
        #
        # @param rate [Float] applied sample rate in `[0.0, 1.0]`
        # @return [Integer] a 56-bit threshold, clamped to `0..(2^56 - 1)`
        def threshold(rate)
          th = ((1.0 - rate) * MAX_THRESHOLD).round
          return 0 if th < 0
          return MAX_ENCODABLE_THRESHOLD if th > MAX_ENCODABLE_THRESHOLD

          th
        end

        # Reconciles Datadog's 64-bit keep/drop decision with the 56-bit threshold it emits.
        #
        # Compressing a 64-bit decision into a 56-bit threshold can flip the re-derived
        # `rv >= th` comparison for a tiny, bounded set of trace ids (at most 128, and none
        # for dyadic rates). When that happens, nudge `rv` just across the threshold boundary
        # so a downstream OpenTelemetry participant reaches the same decision Datadog made.
        #
        # @param random_value [Integer] the Knuth-derived 56-bit random value
        # @param threshold [Integer] the 56-bit threshold being emitted
        # @param kept [Boolean] Datadog's keep (true) / drop (false) decision
        # @return [Integer] a random value consistent with `kept` under `rv >= th`
        def reconcile_random_value(random_value, threshold, kept)
          if kept && random_value < threshold
            threshold
          elsif !kept && random_value >= threshold
            [threshold - 1, 0].max
          else
            random_value
          end
        end

        # Formats a random value as a zero-padded 14-digit hex string.
        def format_random_value(random_value)
          format("%014x", random_value)
        end

        # Formats a threshold as hex with trailing zero nibbles trimmed (never empty).
        def format_threshold(threshold)
          hex = format("%014x", threshold).sub(/0+\z/, "")
          hex.empty? ? "0" : hex
        end

        private_class_method :random_value, :threshold, :reconcile_random_value,
          :format_random_value, :format_threshold
      end
    end
  end
end
