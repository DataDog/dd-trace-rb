# frozen_string_literal: true

module Datadog
  module DI
    # Per-expression capture limits override.
    #
    # Each field is independently optional. The +resolve+ class method
    # walks a per-field fallback chain
    # (expression -> probe -> language default) and returns a fully
    # populated set of limits to pass to the serializer.
    #
    # @api private
    class CaptureLimits
      # @param max_reference_depth [Integer, nil] override for object traversal
      #   depth. nil falls back to the next level in the resolve chain.
      # @param max_collection_size [Integer, nil] override for Array/Hash size cap.
      #   nil falls back to the next level in the resolve chain.
      # @param max_length [Integer, nil] override for String length cap.
      #   nil falls back to the next level in the resolve chain.
      # @param max_field_count [Integer, nil] override for per-object attribute
      #   count cap. nil falls back to the next level in the resolve chain.
      def initialize(max_reference_depth: nil, max_collection_size: nil,
        max_length: nil, max_field_count: nil)
        @max_reference_depth = max_reference_depth
        @max_collection_size = max_collection_size
        @max_length = max_length
        @max_field_count = max_field_count
      end

      # Object traversal depth override, or nil to defer to probe/settings.
      # @return [Integer, nil]
      attr_reader :max_reference_depth

      # Array/Hash size cap override, or nil to defer to probe/settings.
      # @return [Integer, nil]
      attr_reader :max_collection_size

      # String length cap override, or nil to defer to probe/settings.
      # @return [Integer, nil]
      attr_reader :max_length

      # Per-object attribute count cap override, or nil to defer to probe/settings.
      # @return [Integer, nil]
      attr_reader :max_field_count

      # Resolves effective limits for a capture expression by walking
      # the per-field fallback chain:
      #
      #     expr_limits.X ?? probe.max_capture_X ?? settings.dynamic_instrumentation.max_capture_X
      #
      # Resolved independently per field -- a missing field on the
      # expression's limits falls through to the probe level, then to
      # the language-wide default, without affecting the other fields.
      #
      # Returns a Hash with keys :depth, :collection_size, :length,
      # :attribute_count to match the serializer's keyword arguments.
      #
      # @param expr_limits [Datadog::DI::CaptureLimits, nil] per-expression
      #   overrides, or nil to skip the expression level entirely.
      # @param probe [Datadog::DI::Probe] probe carrying probe-level overrides
      #   (max_capture_depth, max_capture_collection_size, max_capture_string_length,
      #   max_capture_attribute_count). Any field may be nil.
      # @param settings [Datadog::Core::Configuration::Settings] tracer settings
      #   providing the dynamic_instrumentation.max_capture_* fallback values.
      # @return [Hash{Symbol => Integer}] fully resolved limits with keys
      #   :depth, :collection_size, :length, :attribute_count.
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
