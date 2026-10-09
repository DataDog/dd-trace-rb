# frozen_string_literal: true

module Datadog
  module DI
    # Logger facade to add the +trace+ method.
    #
    # @api private
    class Logger
      # Initializes the logger facade with the trace-logging gate resolved
      # once from settings and the target logger the facade delegates to.
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

      # Whether trace logging was enabled in settings at construction.
      # @return [Boolean]
      attr_reader :trace_logging
      # The target logger the facade writes to.
      # @return [::Logger]
      attr_reader :target

      # Writes the given message or the block's message to the target
      # logger at debug level. The facade returns nil on every path,
      # matching its void signature.
      #
      # @param args [Array] message or arguments forwarded to the target logger
      # @return [void]
      def debug(*args, &block)
        target.debug(*args, &block) # steep:ignore UnexpectedPositionalArgument
        nil
      end

      # Writes the block's message to the target logger at debug level when
      # the trace-logging gate resolved at construction is enabled; a
      # disabled gate skips the block. The facade returns nil on every
      # path, matching its void signature.
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
