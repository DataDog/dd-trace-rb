# frozen_string_literal: true

module Datadog
  module DI
    # Logger facade to add the +trace+ method.
    #
    # @api private
    class Logger
      # Resolving the trace-logging gate once at construction keeps the
      # per-call settings traversal off the probe hot path. Components are
      # rebuilt on reconfiguration, so the cached value tracks configuration
      # changes.
      #
      # @param settings [Datadog::Core::Configuration::Settings] tracer settings the gate is resolved from
      # @param target [::Logger] logger the facade delegates to
      def initialize(settings, target)
        @trace_logging = settings.dynamic_instrumentation.internal.trace_logging
        @target = target
      end

      attr_reader :trace_logging
      attr_reader :target

      # Writes the block's message to the target logger at debug level. The
      # facade returns nil on every path so void-declared callers do not leak
      # the target's write status.
      #
      # @return [void]
      def debug(&block)
        target.debug(&block)
        nil
      end

      # Writes the block's message to the target logger at debug level when
      # the trace-logging gate resolved at construction is enabled; the block
      # is not invoked otherwise.
      #
      # @return [void]
      def trace
        if trace_logging
          debug { yield }
        end
        nil
      end
    end
  end
end
