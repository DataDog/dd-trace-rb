# frozen_string_literal: true

module Datadog
  module DI
    # Logger facade to add the +trace+ method.
    #
    # @api private
    class Logger
      # Initializes the logger facade with the trace-logging gate resolved
      # once.
      # Resolving the gate at construction keeps the per-call settings
      # traversal off the probe hot path. Components are rebuilt on
      # reconfiguration, so the cached value tracks configuration
      # changes.
      #
      # @param settings [Datadog::Core::Configuration::Settings] tracer settings the gate is resolved from
      # @param target [::Logger] logger the facade delegates to
      def initialize(settings, target)
        @trace_logging = settings.dynamic_instrumentation.internal.trace_logging
        @target = target
      end

      # Whether trace logging is enabled.
      # @return [Boolean]
      attr_reader :trace_logging
      # The target logger.
      # @return [::Logger]
      attr_reader :target

      # Writes the given message or the block's message to the target
      # logger. The facade returns nil on every path,
      # matching its void signature.
      #
      # @param message [String, nil] message written when no block is given
      # @return [void]
      def debug(message = nil, &block)
        target.debug(message, &block)
        nil
      end

      # Writes the block's message to the target logger at debug level when
      # the trace-logging gate resolved at construction is enabled; a
      # disabled gate skips the block.
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
