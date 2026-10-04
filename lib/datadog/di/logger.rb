# frozen_string_literal: true

require "forwardable"

module Datadog
  module DI
    # Logger facade to add the +trace+ method.
    #
    # @api private
    class Logger
      extend Forwardable

      # Resolving the trace-logging gate once at construction keeps the
      # per-call settings traversal off the probe hot path. Components are
      # rebuilt on reconfiguration, so the cached value tracks configuration
      # changes.
      def initialize(settings, target)
        @trace_logging = settings.dynamic_instrumentation.internal.trace_logging
        @target = target
      end

      attr_reader :trace_logging
      attr_reader :target

      def_delegators :target, :debug

      def trace
        if trace_logging
          debug { yield }
        end
      end
    end
  end
end
