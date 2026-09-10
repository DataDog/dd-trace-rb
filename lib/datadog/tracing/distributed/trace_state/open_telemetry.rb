# frozen_string_literal: true

require_relative "../../sampling/rate_sampler"
require_relative "ext"

module Datadog
  module Tracing
    module Distributed
      class TraceState
        # Encodes consistent probability sampling in the OpenTelemetry `ot=` tracestate member.
        # @see https://opentelemetry.io/docs/specs/otel/trace/tracestate-probability-sampling/
        class OpenTelemetry
          class << self
            def from_digest(digest, propagate_sampling: true)
              new(
                random_value: (digest.trace_otel_random_value if propagate_sampling),
                threshold: (digest.trace_otel_threshold if propagate_sampling),
                unknown_fields: digest.trace_otel_unknown_fields,
              )
            end

            # Parses known fields and retains unknown fields for propagation.
            def from_tracestate_member(value)
              return new unless value

              # @type var random_value: ::String?
              # @type var threshold: ::String?
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

              threshold = nil if threshold && !Ext::OpenTelemetry::VALID_THRESHOLD.match?(threshold)
              random_value = nil if random_value && !Ext::OpenTelemetry::VALID_RANDOM_VALUE.match?(random_value)

              new(
                random_value: random_value,
                threshold: threshold,
                unknown_fields: unknown.empty? ? nil : "#{unknown.join(";")};",
              )
            end
          end

          attr_reader :random_value, :threshold, :unknown_fields

          def initialize(random_value: nil, threshold: nil, unknown_fields: nil)
            @random_value = random_value
            @threshold = threshold
            @unknown_fields = unknown_fields
          end

          # Resolves fields that represent the trace's current sampling decision.
          def outbound(
            trace_id:,
            sampling_priority:,
            decision_maker:,
            applied_rate:,
            rate_limiter_rate:,
            distributed_sampling_priority:
          )
            if Ext::OpenTelemetry::NON_PROBABILITY_DECISIONS.include?(decision_maker)
              return self.class.new(random_value: random_value, unknown_fields: unknown_fields)
            end

            trace_kept = sampling_priority && sampling_priority >= Sampling::Ext::Priority::AUTO_KEEP
            if rate_limiter_rate && !trace_kept
              return self.class.new(random_value: random_value, unknown_fields: unknown_fields)
            end

            return self if random_value || threshold
            return self.class.new(unknown_fields: unknown_fields) if distributed_sampling_priority || !applied_rate

            outbound_threshold = threshold_for(applied_rate)
            outbound_random_value = reconcile_random_value(
              random_value_for(trace_id),
              outbound_threshold,
              !!trace_kept
            )
            self.class.new(
              random_value: format_random_value(outbound_random_value),
              threshold: format_threshold(outbound_threshold),
              unknown_fields: unknown_fields,
            )
          end

          def to_s
            fields = []
            fields << "rv:#{random_value}" if random_value
            fields << "th:#{threshold}" if threshold
            fields.concat(unknown_fields.chomp(";").split(";")) if unknown_fields

            value = +""
            fields.each do |field|
              separator = value.empty? ? "" : ";"
              break if value.bytesize + separator.bytesize + field.bytesize > Ext::TRACESTATE_VALUE_SIZE_LIMIT

              value << separator << field
            end
            value.empty? ? "" : "ot=#{value}"
          end

          private

          # Converts Datadog's Knuth hash into OTel's 56-bit random value.
          def random_value_for(trace_id)
            hash = (trace_id * Sampling::RateSampler::KNUTH_FACTOR) % Ext::OpenTelemetry::UINT64_MODULO
            (~hash & Ext::OpenTelemetry::UINT64_MASK) >> 8
          end

          # Converts a sample rate into a 56-bit rejection threshold.
          def threshold_for(rate)
            threshold = ((1.0 - rate) * Ext::OpenTelemetry::MAX_THRESHOLD).round
            return 0 if threshold < 0
            return Ext::OpenTelemetry::MAX_ENCODABLE_THRESHOLD if threshold > Ext::OpenTelemetry::MAX_ENCODABLE_THRESHOLD

            threshold
          end

          # Preserve Datadog's 64-bit decision after expressing it with 56-bit OTel values.
          def reconcile_random_value(random_value, threshold, kept)
            if kept && random_value < threshold
              threshold
            elsif !kept && random_value >= threshold
              [threshold - 1, 0].max
            else
              random_value
            end
          end

          def format_random_value(random_value)
            format("%014x", random_value)
          end

          # OTel thresholds omit trailing zero nibbles but retain leading zeroes.
          def format_threshold(threshold)
            return "0" if threshold.zero?

            trailing_nibbles = ((threshold & -threshold).bit_length - 1) / 4
            (threshold >> (trailing_nibbles * 4)).to_s(16).rjust(14 - trailing_nibbles, "0")
          end
        end
      end
    end
  end
end
