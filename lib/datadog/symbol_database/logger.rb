# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    # Logger facade that adds a config-gated +trace+ method.
    #
    # Wraps any logger (customer-provided or default) and delegates
    # standard methods. The +trace+ method is a sub-debug level that
    # is a no-op unless DD_TRACE_DEBUG is set, avoiding overhead for
    # high-frequency log sites (per-module filtering, dedup checks).
    #
    # +debug+ and +warn+ swallow exceptions from the wrapped target. A
    # customer-provided logger that raises (custom Logger subclass, IO
    # error, frozen state, rspec-mocks stub) must never propagate into
    # SymDB code paths — most callers are on the scheduler thread, which
    # +Component#shutdown!+ joins, and +Thread#join+ re-raises any
    # unhandled thread exception in the caller. Without this defense a
    # misbehaving logger turns into a shutdown-time exception in the
    # customer process. Telemetry-level reporting of the swallowed log
    # error would itself require a working logger, so the swallow is silent.
    #
    # @api private
    class Logger
      # @param settings [Configuration::Settings] Tracer settings (reads trace_logging flag)
      # @param target [::Logger] Underlying logger to delegate to
      def initialize(settings, target)
        @settings = settings
        @target = target
      end

      attr_reader :settings

      # Log at debug. Swallows exceptions from the wrapped target — see class
      # docs.
      # @return [void]
      def debug(*args, &block)
        @target.debug(*args, &block)
      rescue
        nil
      end

      # Log at warn. Swallows exceptions from the wrapped target — see class
      # docs.
      # @return [void]
      def warn(*args, &block)
        @target.warn(*args, &block)
      rescue
        nil
      end

      # Log at trace level (sub-debug). No-op unless trace_logging is enabled.
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
