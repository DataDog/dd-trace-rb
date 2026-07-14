require "datadog/di/spec_helper"
require "datadog/di/capture_expression"
require "datadog/di/capture_expression_evaluator"
require "datadog/di/probe"
require "datadog/di/serializer"
require "datadog/di/redactor"
require "datadog/di/el"
require_relative "serializer_helper"

RSpec.describe Datadog::DI::CaptureExpressionEvaluator do
  di_test

  extend SerializerHelper

  default_settings

  before do
    allow(di_settings).to receive(:max_time_to_serialize_ms).and_return(200)
  end

  let(:redactor) do
    Datadog::DI::Redactor.new(settings)
  end

  let(:serializer) do
    Datadog::DI::Serializer.new(settings, redactor)
  end

  let(:logger) { instance_double(Datadog::Core::Logger).as_null_object }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component).as_null_object }

  let(:evaluator) do
    described_class.new(settings: settings, serializer: serializer, logger: logger, telemetry: telemetry)
  end

  def compile_expression(dsl_string, json)
    compiled = Datadog::DI::EL::Compiler.new.compile(json)
    Datadog::DI::EL::Expression.new(dsl_string, compiled)
  end

  let(:context) do
    Datadog::DI::Context.new(
      probe: probe,
      settings: settings,
      serializer: serializer,
      locals: {x: 42, name: "alice"},
      target_self: nil,
    )
  end

  describe "#evaluate" do
    context "with a single successful expression" do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: "p1", type: :log, type_name: "F", method_name: "m",
          capture_expressions: [
            Datadog::DI::CaptureExpression.new(
              name: "x", expr: compile_expression("x", {"ref" => "x"}),
            ),
          ],
        )
      end

      it "emits the serialized value under the name" do
        output, errors = evaluator.evaluate(probe, context)
        expect(output.keys).to eq(["x"])
        expect(output["x"]).to include(type: "Integer", value: "42")
        expect(errors).to eq([])
      end
    end

    context "expression evaluation raises" do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: "p1", type: :log, type_name: "F", method_name: "m",
          capture_expressions: [
            Datadog::DI::CaptureExpression.new(
              name: "bad_len",
              expr: compile_expression("len(badvar)",
                {"len" => {"ref" => "badvar"}}),
            ),
          ],
        )
      end

      it "omits the key from output and appends to evaluation_errors" do
        output, errors = evaluator.evaluate(probe, context)
        expect(output).to eq({})
        expect(errors.size).to eq(1)
        expect(errors.first[:expr]).to eq("bad_len")
        expect(errors.first[:message]).to include("ExpressionEvaluationError")
      end

      it "logs at debug and reports the exception to telemetry" do
        expect(logger).to receive(:debug) do |&block|
          expect(block.call).to include("bad_len", "evaluation failed", "ExpressionEvaluationError")
        end
        expect(telemetry).to receive(:report).with(
          an_instance_of(Datadog::DI::Error::ExpressionEvaluationError),
          description: "DI capture-expression evaluation failed",
        )
        evaluator.evaluate(probe, context)
      end
    end

    context "expression evaluation raises a non-StandardError" do
      let(:expr) { instance_double(Datadog::DI::EL::Expression) }

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "p1", type: :log, type_name: "F", method_name: "m",
          capture_expressions: [
            Datadog::DI::CaptureExpression.new(name: "boom", expr: expr),
          ],
        )
      end

      before do
        allow(expr).to receive(:evaluate).and_raise(NotImplementedError, "nope")
      end

      it "catches it, omits the key, and records an evaluation error" do
        output, errors = evaluator.evaluate(probe, context)
        expect(output).to eq({})
        expect(errors.size).to eq(1)
        expect(errors.first[:expr]).to eq("boom")
        expect(errors.first[:message]).to include("NotImplementedError")
      end
    end

    context "expression evaluation raises a fatal exception" do
      let(:expr) { instance_double(Datadog::DI::EL::Expression) }

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "p1", type: :log, type_name: "F", method_name: "m",
          capture_expressions: [
            Datadog::DI::CaptureExpression.new(name: "boom", expr: expr),
          ],
        )
      end

      before do
        allow(expr).to receive(:evaluate).and_raise(SystemExit.new)
      end

      it "re-raises the fatal exception instead of recording an error" do
        expect { evaluator.evaluate(probe, context) }.to raise_error(SystemExit)
      end
    end

    context "mixed success and failure" do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: "p1", type: :log, type_name: "F", method_name: "m",
          capture_expressions: [
            Datadog::DI::CaptureExpression.new(
              name: "ok", expr: compile_expression("x", {"ref" => "x"}),
            ),
            Datadog::DI::CaptureExpression.new(
              name: "fail",
              expr: compile_expression("len(badvar)",
                {"len" => {"ref" => "badvar"}}),
            ),
          ],
        )
      end

      it "succeeds for the good one, errors for the bad one" do
        output, errors = evaluator.evaluate(probe, context)
        expect(output.keys).to eq(["ok"])
        expect(errors.size).to eq(1)
        expect(errors.first[:expr]).to eq("fail")
      end
    end

    context "time budget exhausted before evaluating any" do
      before do
        allow(di_settings).to receive(:max_time_to_serialize_ms).and_return(0)
      end

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "p1", type: :log, type_name: "F", method_name: "m",
          capture_expressions: [
            Datadog::DI::CaptureExpression.new(
              name: "x", expr: compile_expression("x", {"ref" => "x"}),
            ),
            Datadog::DI::CaptureExpression.new(
              name: "y", expr: compile_expression("name", {"ref" => "name"}),
            ),
          ],
        )
      end

      it "emits notCapturedReason:timeout stubs for all expressions" do
        output, errors = evaluator.evaluate(probe, context)
        expect(output["x"]).to eq(notCapturedReason: "timeout")
        expect(output["y"]).to eq(notCapturedReason: "timeout")
        expect(errors).to eq([])
      end

      it "increments the timeout telemetry counter for each timed-out expression" do
        expect(telemetry).to receive(:inc).with(
          "dynamic_instrumentation", "capture_expressions_skipped_by_timeout", 1,
        ).twice
        evaluator.evaluate(probe, context)
      end
    end

    context "time budget exhausted mid-loop after some expressions have evaluated" do
      before do
        allow(di_settings).to receive(:max_time_to_serialize_ms).and_return(100)
        clock_calls = 0
        clock_returns = [0, 0, 200_000_000]
        allow(::Process).to receive(:clock_gettime).and_wrap_original do |original, *args|
          if args == [::Process::CLOCK_MONOTONIC, :nanosecond]
            clock_returns[clock_calls].tap { clock_calls += 1 }
          else
            original.call(*args)
          end
        end
      end

      let(:probe) do
        Datadog::DI::Probe.new(
          id: "p1", type: :log, type_name: "F", method_name: "m",
          capture_expressions: [
            Datadog::DI::CaptureExpression.new(
              name: "x", expr: compile_expression("x", {"ref" => "x"}),
            ),
            Datadog::DI::CaptureExpression.new(
              name: "y", expr: compile_expression("name", {"ref" => "name"}),
            ),
          ],
        )
      end

      it "evaluates the first expression and times out the second" do
        output, errors = evaluator.evaluate(probe, context)
        expect(output["x"]).to include(type: "Integer", value: "42")
        expect(output["y"]).to eq(notCapturedReason: "timeout")
        expect(errors).to eq([])
      end

      it "increments the timeout counter only for the timed-out expression" do
        expect(telemetry).to receive(:inc).with(
          "dynamic_instrumentation", "capture_expressions_skipped_by_timeout", 1,
        ).once
        evaluator.evaluate(probe, context)
      end
    end

    context "per-expression depth limit overrides probe-level depth" do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: "p1", type: :log, type_name: "F", method_name: "m",
          max_capture_depth: 1,
          capture_expressions: [
            Datadog::DI::CaptureExpression.new(
              name: "deep", expr: compile_expression("x", {"ref" => "x"}),
              limits: Datadog::DI::CaptureLimits.new(max_reference_depth: 5),
            ),
          ],
        )
      end

      it "passes the expression's depth into the serializer" do
        expect(serializer).to receive(:serialize_value).with(42, hash_including(depth: 5, attribute_count: 10)).and_call_original
        evaluator.evaluate(probe, context)
      end
    end
  end
end
