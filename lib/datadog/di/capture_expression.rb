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
      def initialize(name:, expr:, limits: nil)
        @name = name
        @expr = expr
        @limits = limits
      end

      attr_reader :name
      attr_reader :expr
      attr_reader :limits
    end
  end
end
