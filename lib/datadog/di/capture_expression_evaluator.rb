# frozen_string_literal: true

require_relative "capture_expression"
require_relative "capture_limits"
require_relative "capture_expression_evaluator/result"
require_relative "evaluation_failure"
require_relative "fatal_exceptions"
require_relative "capture_expression"
require_relative "capture_limits"
require_relative "capture_expression_evaluator/result"
require_relative "evaluation_failure"
require_relative "fatal_exceptions"
require_relative "guardrails_telemetry"
require_relative "../core/utils/time"
require_relative "el"

module Datadog
  module DI
    class CaptureExpressionEvaluator
      # Initializes the evaluator.
      #
      # @param settings [Datadog::Core::Configuration::Settings] tracer settings
      # @param serializer [Serializer] serializer for captured expression values
      # @param logger [DI::Logger] logger for evaluation failure diagnostics
      # @param guardrails_telemetry [GuardrailsTelemetry] emitter for the canonical capture-timeout skip metric
      # @param telemetry [Datadog::Core::Telemetry::Component, nil] component evaluation failures are reported through
      # @return [void]
      def initialize(settings:, serializer:, logger:, guardrails_telemetry:, telemetry: nil)
        @settings = settings
        @serializer = serializer
        @logger = logger
        @guardrails_telemetry = guardrails_telemetry
        @telemetry = telemetry
      end

      attr_reader :settings

      attr_reader :serializer

      attr_reader :logger

      # The guardrails metric emitter.
      # @return [GuardrailsTelemetry]
      attr_reader :guardrails_telemetry

      attr_reader :telemetry

      # Evaluates each of the probe's capture expressions against the given
      # context, serializing the captured values under one capture deadline
      # resolved through the serializer and shared across all expressions.
      # An expression that fails to evaluate or serialize contributes an entry
      # to the returned errors.
      #
      # A fresh evaluation deadline is resolved once for the whole
      # capture-expression phase and threaded into every expression, so
      # capture-expression evaluation is bounded identically for line and
      # method probes. An expression whose evaluation exceeds the deadline
      # is reported as an evaluation error, like any other evaluation
      # failure.
      #
      # @param probe [Probe] the probe whose capture expressions are evaluated
      # @param context [Context] evaluation context the expressions are evaluated against
      # @return [Result] the evaluation result: the serialized values keyed by
      #   capture expression name and the errors of the expressions that failed
      #   to evaluate or serialize
      def evaluate(probe, context)
        deadline = serializer.serialization_deadline
        evaluation_deadline = EL::Evaluator.evaluation_deadline(settings)

        output = {}
        evaluation_errors = []

        probe.capture_expressions.each do |capture_expression|
          name = capture_expression.name

          if Core::Utils::Time.get_time >= deadline
            output[name] = {notCapturedReason: "timeout"}
            telemetry&.inc(DI::TELEMETRY_NAMESPACE, "capture_expressions_skipped_by_timeout", 1)
            guardrails_telemetry.skipped(
              reason: GuardrailsTelemetry::Reason::EVALUATION_TIMEOUT,
              probe: probe,
            )
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
              deadline: deadline,
            )
          rescue Exception => exc # standard:disable Lint/RescueException
            Datadog::DI.reraise_if_fatal(exc)
            evaluation_errors << EvaluationFailure.new(expr: name, message: "#{exc.class}: #{exc.message}")
            logger.debug do
              "di: probe #{probe.id}: capture expression #{name}: evaluation failed: #{exc.class}: #{exc.message}"
            end
            telemetry&.report(exc, description: "DI capture-expression evaluation failed")
          end
        end

        Result.new(serialized_values: output, errors: evaluation_errors)
      end
    end
  end
end
