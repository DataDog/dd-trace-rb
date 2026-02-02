# frozen_string_literal: true

require_relative 'metrics'

module Datadog
  module AppSec
    # Request-bound context providing threat detection interface.
    #
    # Activated at the start of a request (see `Contrib::Rack::RequestMiddleware`)
    # and shared across all instrumentations within that request's lifecycle.
    #
    # Accumulates security events, metrics, and state needed for coordinated
    # threat detection.
    #
    # @api private
    class Context
      # Steep: https://github.com/soutaro/steep/issues/1880
      ActiveContextError = Class.new(StandardError) # steep:ignore IncompatibleAssignment

      # TODO: add delegators for active trace span
      attr_reader :trace, :span

      # Shared mutable storage for counters, flags, and data accumulated during
      # the request's lifecycle.
      attr_reader :state

      class << self
        def activate(context)
          raise ArgumentError, 'not a Datadog::AppSec::Context' unless context.instance_of?(Context)
          raise ActiveContextError, 'another context is active, nested contexts are not supported' if active

          Thread.current[Ext::ACTIVE_CONTEXT_KEY] = context
        end

        def deactivate
          active&.finalize!
        ensure
          Thread.current[Ext::ACTIVE_CONTEXT_KEY] = nil
        end

        def active
          Thread.current[Ext::ACTIVE_CONTEXT_KEY]
        end
      end

      def initialize(trace, span, waf_runner)
        @trace = trace
        @span = span
        @waf_runner = waf_runner
        @metrics = Metrics::Collector.new
        @state = {
          events: [],
          interrupted: false
        }
      end

      def run_waf(persistent_data, ephemeral_data, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT)
        result = @waf_runner.run(persistent_data, ephemeral_data, timeout)

        @metrics.record_waf(result)
        result
      end

      def run_rasp(type, persistent_data, ephemeral_data, timeout = WAF::LibDDWAF::DDWAF_RUN_TIMEOUT, phase: nil)
        result = @waf_runner.run(persistent_data, ephemeral_data, timeout)

        Metrics::Telemetry.report_rasp(type, result, phase: phase)
        @metrics.record_rasp(result, type: type, phase: phase)

        result
      end

      def events
        @state[:events]
      end

      def mark_as_interrupted!
        @state[:interrupted] = true
      end

      def interrupted?
        @state[:interrupted]
      end

      def waf_runner_ruleset_version
        @waf_runner.ruleset_version
      end

      def waf_runner_known_addresses
        @waf_runner.waf_addresses
      end

      def extract_schema
        @waf_runner.run({'waf.context.processor' => {'extract-schema' => true}}, {})
      end

      def export_metrics
        return if @span.nil?

        Metrics::Exporter.export_waf_metrics(@metrics.waf, @span)
        Metrics::Exporter.export_rasp_metrics(@metrics.rasp, @span)
      end

      def export_request_telemetry
        return if @trace.nil?

        Metrics::TelemetryExporter.export_waf_request_metrics(@metrics.waf, self)
      end

      def finalize!
        @waf_runner.finalize!
      end
    end
  end
end
