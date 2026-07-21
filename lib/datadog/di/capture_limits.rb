# frozen_string_literal: true

module Datadog
  module DI
    class CaptureLimits
      def initialize(max_reference_depth: nil, max_collection_size: nil,
        max_length: nil, max_field_count: nil)
        @max_reference_depth = max_reference_depth
        @max_collection_size = max_collection_size
        @max_length = max_length
        @max_field_count = max_field_count
      end

      attr_reader :max_reference_depth

      attr_reader :max_collection_size

      attr_reader :max_length

      attr_reader :max_field_count

      def self.resolve(expr_limits:, probe:, settings:)
        di = settings.dynamic_instrumentation
        {
          depth: expr_limits&.max_reference_depth ||
            probe.max_capture_depth ||
            di.max_capture_depth,
          collection_size: expr_limits&.max_collection_size ||
            probe.max_capture_collection_size ||
            di.max_capture_collection_size,
          length: expr_limits&.max_length ||
            probe.max_capture_string_length ||
            di.max_capture_string_length,
          attribute_count: expr_limits&.max_field_count ||
            probe.max_capture_attribute_count ||
            di.max_capture_attribute_count,
        }
      end
    end
  end
end
