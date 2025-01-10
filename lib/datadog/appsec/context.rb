# frozen_string_literal: true

module Datadog
  module AppSec
    # This class accumulates the context over the request life-cycle and exposes
    # interface sufficient for instrumentation to perform threat detection.
    class Context
      ActiveContextError = Class.new(StandardError)

      # XXX: Continue from here:
      #        1. Replace naming of processor_context into waf_runner
      #        2. Replace calls of waf run
      attr_reader :trace, :span, :processor_context

      class << self
        def activate(context)
          raise ArgumentError, 'not a Datadog::AppSec::Context' unless context.instance_of?(Context)
          raise ActiveContextError, 'another context is active, nested contexts are not supported' if active

          Thread.current[Ext::ACTIVE_CONTEXT_KEY] = context
        end

        def deactivate
          active&.finalize
        ensure
          Thread.current[Ext::ACTIVE_CONTEXT_KEY] = nil
        end

        def active
          Thread.current[Ext::ACTIVE_CONTEXT_KEY]
        end
      end

      def initialize(trace, span, security_engine)
        @trace = trace
        @span = span
        @security_engine = security_engine
        @waf_runner = security_engine.new_context

        # FIXME: Left for compatibility now
        @processor_context = @waf_runner
      end

      def run_waf(persistent_data, ephemeral_data, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
        @waf_runner.run(persistent_data, ephemeral_data, timeout)
      end

      def run_rasp(_type, persistent_data, ephemeral_data, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
        @waf_runner.run(persistent_data, ephemeral_data, timeout)
      end

      def finalize
        @waf_runner.finalize
      end
    end
  end
end
