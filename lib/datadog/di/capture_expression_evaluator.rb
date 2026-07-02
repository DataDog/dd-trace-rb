# frozen_string_literal: true

require_relative "capture_expression"
require_relative "capture_limits"
require_relative "fatal_exceptions"

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
    # Go DI).
    #
    # On per-fire time-budget exhaustion, remaining expressions emit a
    # stub `{ "notCapturedReason" => "timeout" }` entry, matching the
    # Node.js DI shape.
    #
    # @api private
    class CaptureExpressionEvaluator
      TELEMETRY_NAMESPACE = "dynamic_instrumentation"

      # @param settings [Datadog::Core::Configuration::Settings]
      # @param serializer [Datadog::DI::Serializer]
      # @param logger [Datadog::DI::Logger]
      # @param telemetry [Datadog::Core::Telemetry::Component, nil] nil is
      #   legitimate — Component.build accepts nil telemetry when DI is used
      #   outside a telemetry-configured environment, and Component threads
      #   the nil through to here. All telemetry calls below are nil-guarded.
      def initialize(settings:, serializer:, logger:, telemetry: nil)
        @settings = settings
        @serializer = serializer
        @logger = logger
        @telemetry = telemetry
      end

      # Tracer settings; the `dynamic_instrumentation.max_time_to_serialize_ms`
      # field is read on every #evaluate call to compute the per-fire deadline.
      # @return [Datadog::Core::Configuration::Settings]
      attr_reader :settings

      # Serializer used to convert evaluated expression values into the
      # snapshot wire format.
      # @return [Datadog::DI::Serializer]
      attr_reader :serializer

      # Logger used for debug-level reporting of per-expression evaluation
      # failures.
      # @return [Datadog::DI::Logger]
      attr_reader :logger

      # Telemetry component used to report capture-expression timeouts (inc)
      # and per-expression evaluation exceptions (report). nil when DI was
      # constructed without telemetry; all call sites guard with `&.`.
      # @return [Datadog::Core::Telemetry::Component, nil]
      attr_reader :telemetry

      # Evaluate +probe.capture_expressions+ against +context+.
      #
      # @param probe [Datadog::DI::Probe]
      # @param context [Datadog::DI::Context]
      # @return [Array(Hash, Array)] pair of
      #   - the `captureExpressions` block ({ name => serialized_value })
      #   - the per-expression evaluation_errors array
      def evaluate(probe, context)
        budget_ns = settings.dynamic_instrumentation.max_time_to_serialize_ms * 1_000_000
        deadline_ns = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) + budget_ns

        output = {}
        evaluation_errors = []

        probe.capture_expressions.each do |capture_expression|
          name = capture_expression.name

          if ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, :nanosecond) >= deadline_ns
            output[name] = {notCapturedReason: "timeout"}
            # Counter is per-expression: a single probe fire with N expressions
            # that all time out increments by N. The metric name reflects the
            # unit ("expressions skipped"), not "fires timed out".
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
