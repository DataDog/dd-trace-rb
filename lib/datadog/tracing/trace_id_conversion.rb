# frozen_string_literal: true

# typed: ignore

module Datadog
  module Tracing
    # The module handles bitwise operation for trace id
    module TraceIdConversion
      module_function

      def to_high_order(trace_id)
        trace_id >> 64
      end

      def to_low_order(trace_id)
        trace_id & 0xFFFFFFFFFFFFFFFF
      end

      def concatenate(high_order, low_order)
        high_order << 64 | low_order
      end
    end
  end
end
