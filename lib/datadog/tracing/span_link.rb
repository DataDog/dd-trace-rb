# frozen_string_literal: true

module Datadog
  module Tracing
    # SpanLink represents a causal link between two spans.
    # @public_api
    class SpanLink
      # @!attribute [r] span_id
      #   Datadog id for the currently active span.
      #   @return [Integer]
      attr_reader :span_id

      # @!attribute [r] trace_id
      #   Datadog id for the currently active trace.
      #   @return [Integer]
      attr_reader :trace_id

      # @!attribute [r] attributes
      #   Datadog-specific tags that support richer distributed tracing association.
      #   @return [Hash<String,String>]
      attr_reader :attributes

      # @!attribute [r] trace_flags
      #   The W3C "trace-flags" extracted from a distributed context. This field is an 8-bit unsigned integer.
      #   @return [Integer]
      #   @see https://www.w3.org/TR/trace-context/#trace-flags
      attr_reader :trace_flags

      # @!attribute [r] trace_state
      #   The W3C "tracestate" extracted from a distributed context.
      #   This field is a string representing vendor-specific distribution data.
      #   The `dd=` entry is removed from `trace_state` as its value is dynamically calculated
      #   on every propagation injection.
      #   @return [String]
      #   @see https://www.w3.org/TR/trace-context/#tracestate-header
      attr_reader :trace_state

      def initialize(
        span_id: nil,
        trace_id: nil,
        attributes: nil,
        trace_flags: nil,
        trace_state: nil
      )
        @span_id = span_id
        @trace_id = trace_id
        @attributes = attributes && attributes.dup.freeze
        @trace_flags = trace_flags
        @trace_state = trace_state && trace_state.dup.freeze
        @dropped_attributes = 0
        freeze
      end

      def to_hash
        h = {
          span_id: @span_id,
          trace_id: Tracing::Utils::TraceId.to_low_order(@trace_id),

        }
        # Optimization: Hash non empty attributes
        if @trace_id.to_i > Tracing::Utils::EXTERNAL_MAX_ID
          h[:trace_id_high] =
            Tracing::Utils::TraceId.to_high_order(@trace_id)
        end
        if @attributes
          h[:attributes] = {}
          @attributes.each do |k1, v1|
            Tracing::Utils.serialize_attribute(k1, v1).each do |new_k1, value|
              h[:attributes][new_k1] = value.to_s
            end
          end
        end
        h[:dropped_attributes_count] = @dropped_attributes if @dropped_attributes > 0
        h[:tracestate] = @trace_state if @trace_state
        # If traceflags set, the high bit (bit 31) should be set to 1 (uint32).
        # This helps us distinguish between when the sample decision is zero or not set
        h[:flags] = if @trace_flags.nil?
                      0
                    else
                      @trace_flags | (1 << 31)
                    end
        h
      end
    end
  end
end
