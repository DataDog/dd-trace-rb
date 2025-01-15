# frozen_string_literal: true

module Datadog
  module AppSec
    # This class accumulates the context over the request life-cycle and exposes
    # interface sufficient for instrumentation to perform threat detection.
    class Context
      ActiveContextError = Class.new(StandardError)
      WAFMetrics = Struct.new(:timeouts, :duration_ns, :duration_ext_ns, keyword_init: true)

      attr_reader :trace, :span, :waf_metrics

      # NOTE: This is an intermediate state and will be changed
      attr_reader :waf_runner

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
        @waf_runner = security_engine.new_runner
        @waf_metrics = WAFMetrics.new(timeouts: 0, duration_ns: 0, duration_ext_ns: 0)
        @mutex = Mutex.new
      end

      def run_waf(persistent_data, ephemeral_data, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
        result = @waf_runner.run(persistent_data, ephemeral_data, timeout)

        @mutex.synchronize do
          @waf_metrics.timeouts += 1 if result.timeout?
          @waf_metrics.duration_ns += result.duration_ns
          @waf_metrics.duration_ext_ns += result.duration_ext_ns
        end

        result
      end

      def run_rasp(_type, persistent_data, ephemeral_data, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
        @waf_runner.run(persistent_data, ephemeral_data, timeout)
      end

      def extract_schema
        @waf_runner.run({ 'waf.context.processor' => { 'extract-schema' => true } }, {})
      end

      def finalize
        @waf_runner.finalize
      end
    end
  end
end
