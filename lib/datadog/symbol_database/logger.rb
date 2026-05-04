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

      # @param settings [Configuration::Settings] Tracer settings (reads trace_logging flag)
      # @param target [::Logger] Underlying logger to delegate to
      def initialize(settings, target)
        @settings = settings
        @target = target
      end

      attr_reader :settings

      # Only debug and warn are delegated by design — symbol database
      # extraction logs only at debug (high-volume diagnostics) and warn
      # (user-actionable problems). Adding info/error would invite
      # log-level drift; explicit additions can be made if needed.
      def_delegators :@target, :debug, :warn

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
