# frozen_string_literal: true

require_relative "capture_expression"
require_relative "capture_limits"
require_relative "fatal_exceptions"
require_relative "guardrails_telemetry"
require_relative "telemetry_namespace"

module Datadog
  module DI
    class CaptureExpressionEvaluator
      # Initializes the evaluator with the settings, serializer, logger
      # and telemetry components the capture expressions are evaluated
      # against.
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

      # The guardrails skip-metric emitter.
      # @return [GuardrailsTelemetry]
      attr_reader :guardrails_telemetry

      attr_reader :telemetry

      # Evaluates each of the probe's capture expressions against the given
      # context and serializes the captured values, enforcing the capture
      # time budget between expressions. An expression that fails to evaluate
      # or serialize contributes an entry to the returned errors instead of
      # the output.
      #
      # @param probe [Probe] the probe whose capture expressions are evaluated
      # @param context [Context] evaluation context the expressions are evaluated against
      # @return [Array(Hash, Array)] the serialized values keyed by expression name and the evaluation errors
      def evaluate(probe, context)
        budget_ns = settings.dynamic_instrumentation.max_time_to_serialize_ms * 1_000_000
        deadline_ns = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) + budget_ns

        output = {}
        evaluation_errors = []

        probe.capture_expressions.each do |capture_expression|
          name = capture_expression.name

          if ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) >= deadline_ns
            output[name] = {notCapturedReason: "timeout"}
            telemetry&.inc(DI::TELEMETRY_NAMESPACE, "capture_expressions_skipped_by_timeout", 1)
            guardrails_telemetry.skipped(
              reason: GuardrailsTelemetry::Reason::EVALUATION_TIMEOUT,
              probe: probe,
              probe_id: probe.id,
            )
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
