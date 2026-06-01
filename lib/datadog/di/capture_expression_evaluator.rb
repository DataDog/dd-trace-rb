# frozen_string_literal: true

require_relative "capture_expression"

module Datadog
  module DI
    # Evaluates a probe's capture expressions against a captured context
    # and serializes their results into a shape suitable for the
    # `captureExpressions` block of a snapshot.
    #
    # On per-expression evaluation/serialization failure, the expression's
    # key is omitted from the output and an `{ expr: name, message: ... }`
    # entry is appended to the returned `evaluation_errors` array. This
    # matches the cross-tracer convention (Python, Java, .NET, Node.js,
    # Go DI) — see
    # projects/capture-expressions/specs/wire-format.md §8.8 and
    # projects/capture-expressions/design/decisions.md (D5).
    #
    # On per-fire time-budget exhaustion, remaining expressions emit a
    # stub `{ "notCapturedReason" => "timeout" }` entry (Node.js shape;
    # see D4).
    #
    # @api private
    class CaptureExpressionEvaluator
      # @param settings [Datadog::Core::Configuration::Settings]
      # @param serializer [Datadog::DI::Serializer]
      # @param telemetry [Datadog::Core::Telemetry::Component, nil]
      def initialize(settings:, serializer:, telemetry: nil)
        @settings = settings
        @serializer = serializer
        @telemetry = telemetry
      end

      attr_reader :settings
      attr_reader :serializer
      attr_reader :telemetry

      # Evaluate +probe.capture_expressions+ against +context+.
      #
      # @param probe [Datadog::DI::Probe]
      # @param context [Datadog::DI::Context]
      # @return [Array(Hash, Array)] pair of
      #   - the `captureExpressions` block ({ name => serialized_value })
      #   - the per-expression evaluation_errors array
      def evaluate(probe, context)
        budget_ns = settings.dynamic_instrumentation.capture_expression_timeout_ms * 1_000_000
        deadline_ns = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) + budget_ns

        output = {}
        evaluation_errors = []

        probe.capture_expressions.each do |capture_expression|
          name = capture_expression.name

          if ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) >= deadline_ns
            output[name] = {notCapturedReason: "timeout"}
            telemetry&.inc("dynamic_instrumentation.capture_expression_timeout", 1)
            next
          end

          begin
            value = capture_expression.expr.evaluate(context)
            limits = CaptureLimits.resolve(
              expr_limits: capture_expression.limits,
              probe: probe,
              settings: settings,
            )
            # NOTE: only depth and attribute_count are threaded through to
            # the serializer here; max_length and max_collection_size are
            # read from settings directly inside Serializer#serialize_value
            # and are not yet overridable per expression. Fixing this
            # requires adding length / collection_size kwargs to
            # Serializer#serialize_value and its recursive call sites.
            # Tracked as a follow-up in projects/capture-expressions/backlog.
            output[name] = serializer.serialize_value(
              value, name: name,
              depth: limits[:depth],
              attribute_count: limits[:attribute_count],
            )
          rescue => exc
            evaluation_errors << {expr: name, message: "#{exc.class}: #{exc.message}"}
            Datadog.logger.debug do
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
