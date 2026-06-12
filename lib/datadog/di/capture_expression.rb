# frozen_string_literal: true

require_relative "capture_limits"

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
      # @param name [String] user-supplied key under which this expression's
      #   serialized value appears in the snapshot's captureExpressions block.
      #   Validated against /\A[a-zA-Z0-9_?]+\z/ by ProbeBuilder.
      # @param expr [Datadog::DI::EL::Expression] compiled DSL expression
      #   evaluated against the probe context at probe-fire time.
      # @param limits [Datadog::DI::CaptureLimits, nil] optional per-expression
      #   capture-limit overrides. nil falls back to probe-level then
      #   settings-level limits independently per field via CaptureLimits.resolve.
      def initialize(name:, expr:, limits: nil)
        @name = name
        @expr = expr
        @limits = limits
      end

      # User-supplied snapshot key. See `initialize` for charset constraints.
      # @return [String]
      attr_reader :name

      # Compiled DI expression-language expression evaluated at probe-fire time.
      # @return [Datadog::DI::EL::Expression]
      attr_reader :expr

      # Per-expression capture-limit overrides, or nil when none are configured.
      # @return [Datadog::DI::CaptureLimits, nil]
      attr_reader :limits
    end
  end
end
