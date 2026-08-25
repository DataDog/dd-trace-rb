# frozen_string_literal: true

require_relative "capture_expression"
require_relative "capture_limits"
require_relative "fatal_exceptions"

module Datadog
  module DI
    class CaptureExpressionEvaluator
      TELEMETRY_NAMESPACE = "dynamic_instrumentation"

      def initialize(settings:, serializer:, logger:, telemetry: nil)
        @settings = settings
        @serializer = serializer
        @logger = logger
        @telemetry = telemetry
      end

      attr_reader :settings

      attr_reader :serializer

      attr_reader :logger

      attr_reader :telemetry

      def evaluate(probe, context)
        budget_ns = settings.dynamic_instrumentation.max_time_to_serialize_ms * 1_000_000
        deadline_ns = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) + budget_ns

        output = {}
        evaluation_errors = []

        probe.capture_expressions.each do |capture_expression|
          name = capture_expression.name

          if ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) >= deadline_ns
            output[name] = {notCapturedReason: "timeout"}
            telemetry&.inc(TELEMETRY_NAMESPACE, "capture_expressions_skipped_by_timeout", 1)
            next
          end

          begin
            value = capture_expression.expr.evaluate(context)
            limits = CaptureLimits.resolve(
              expr_limits: capture_expression.limits,
              probe: probe,
              settings: settings,
            )
            output[name] = serializer.serialize_value(
              value, name: name,
              depth: limits[:depth],
              attribute_count: limits[:attribute_count],
              length: limits[:length],
              collection_size: limits[:collection_size],
            )
          rescue Exception => exc # standard:disable Lint/RescueException
            Datadog::DI.reraise_if_fatal(exc)
            evaluation_errors << {expr: name, message: "#{exc.class}: #{exc.message}"}
            logger.debug do
              "di: probe #{probe.id}: capture expression #{name}: evaluation failed: #{exc.class}: #{exc.message}"
            end
            telemetry&.report(exc, description: "DI capture-expression evaluation failed")
          end
        end

        [output, evaluation_errors]
      end
    end
  end
end
