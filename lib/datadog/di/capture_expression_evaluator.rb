# frozen_string_literal: true

require_relative "capture_expression"
require_relative "capture_limits"
require_relative "fatal_exceptions"
require_relative "el"

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

      # Evaluates each of the probe's capture expressions against +context+,
      # serializing each evaluated value, and returns the serialized values
      # keyed by expression name together with the evaluation errors.
      #
      # A fresh evaluation deadline is resolved once for the whole
      # capture-expression phase and threaded into every expression, so
      # capture-expression evaluation is bounded identically for line and
      # method probes. An expression whose evaluation exceeds the deadline
      # is reported as an evaluation error, like any other evaluation
      # failure.
      #
      # @param probe [Probe] the probe whose capture expressions are
      #   evaluated.
      # @param context [Context] evaluation context for the capture
      #   expressions.
      # @return [Array(Hash, Array)] the serialized capture values keyed by
      #   expression name, and the evaluation errors.
      def evaluate(probe, context)
        budget_ns = settings.dynamic_instrumentation.max_time_to_serialize_ms * 1_000_000
        deadline_ns = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) + budget_ns
        evaluation_deadline = EL::Evaluator.evaluation_deadline(settings)

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
            value = capture_expression.expr.evaluate(context, deadline: evaluation_deadline)
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
