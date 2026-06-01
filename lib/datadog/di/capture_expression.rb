# frozen_string_literal: true

module Datadog
  module DI
    # Configured capture expression on a log probe.
    #
    # Carries a user-supplied +name+ (used as the key in the snapshot
    # output), a compiled +expr+ from the DI expression language, and
    # optional per-expression +limits+ overriding the probe-level
    # capture limits.
    #
    # Pure value object: every attribute round-trips through remote
    # configuration and the snapshot payload; no in-process-only fields.
    #
    # @api private
    class CaptureExpression
      def initialize(name:, expr:, limits: nil)
        @name = name
        @expr = expr
        @limits = limits
      end

      attr_reader :name
      attr_reader :expr
      attr_reader :limits
    end

    # Per-expression CaptureLimits override.
    #
    # Each field is independently optional. The +resolve+ class method
    # walks a per-field fallback chain
    # (expression -> probe -> language default) and returns a fully
    # populated set of limits to pass to the serializer.
    #
    # @api private
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

      # Resolves effective limits for a capture expression by walking
      # the per-field fallback chain:
      #
      #     expr_limits.X ?? probe.max_capture_X ?? settings.dynamic_instrumentation.max_capture_X
      #
      # Resolved independently per field — a missing field on the
      # expression's limits falls through to the probe level, then to
      # the language-wide default, without affecting the other fields.
      #
      # Returns a Hash with keys :depth, :collection_size, :length,
      # :attribute_count to match the serializer's keyword arguments.
      def self.resolve(expr_limits:, probe:, settings:)
        di = settings.dynamic_instrumentation
        {
          depth: expr_limits&.max_reference_depth ||
            probe.max_capture_depth ||
            di.max_capture_depth,
          collection_size: expr_limits&.max_collection_size ||
            di.max_capture_collection_size,
          length: expr_limits&.max_length ||
            di.max_capture_string_length,
          attribute_count: expr_limits&.max_field_count ||
            probe.max_capture_attribute_count ||
            di.max_capture_attribute_count,
        }
      end
    end
  end
end
