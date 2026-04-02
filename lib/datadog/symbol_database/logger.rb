# frozen_string_literal: true

require 'forwardable'

module Datadog
  module SymbolDatabase
    # Logger facade that adds a config-gated +trace+ method.
    #
    # Wraps any logger (customer-provided or default) and delegates
    # standard methods. The +trace+ method is a sub-debug level that
    # is a no-op unless DD_TRACE_DEBUG is set, avoiding overhead for
    # high-frequency log sites (per-module filtering, dedup checks).
    #
    # @api private
    class Logger
      extend Forwardable

      def initialize(settings, target)
        @settings = settings
        @target = target
      end

      attr_reader :settings
      attr_reader :target

      def_delegators :target, :debug, :warn

      # Log at trace level (sub-debug). No-op unless DD_TRACE_DEBUG is set.
      # @yield Block that returns the log message string
      # @return [void]
      def trace(&block)
        if settings.symbol_database.internal.trace_logging
          debug(&block)
        end
      end
    end
  end
end
