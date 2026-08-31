# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/evaluation_engine"

RSpec.describe Datadog::OpenFeature::EvaluationEngine do
  before do
    allow(Datadog::OpenFeature::NativeEvaluator).to receive(:new).and_return(evaluator)
    allow(evaluator).to receive(:observe_full_evaluation_data).and_return(false)
  end

  let(:engine) { described_class.new(reporter, telemetry: telemetry, logger: logger) }
  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:logger) { instance_double(Datadog::Core::Logger) }
  let(:evaluator) { instance_double(Datadog::OpenFeature::NativeEvaluator) }
  let(:observe_full_evaluation_data_key) do
    Datadog::OpenFeature::Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA
  end
  let(:configuration) do
    <<~JSON
      {
        "id": "1",
        "createdAt": "2024-04-17T19:40:53.716Z",
        "format": "SERVER",
        "environment": { "name": "test" },
        "flags": {
          "test_flag": {
            "key": "test",
            "enabled": true,
            "variationType": "STRING",
            "variations": {
              "control": { "key": "control", "value": "hello" }
            },
            "allocations": [
              {
                "key": "rollout",
                "splits": [{ "variationKey": "control", "shards": [] }],
                "doLog": false
              }
            ]
          }
        }
      }
    JSON
  end

  describe "#fetch_value" do
    let(:result) { engine.fetch_value("test", default_value: "fallback", expected_type: :string) }

    context "when binding evaluator is not ready" do
      it "returns evaluation error and reports exposure" do
        expect(reporter).to receive(:report).with(kind_of(Datadog::OpenFeature::ResolutionDetails), flag_key: "test", context: nil)

        expect(result.value).to eq("fallback")
        expect(result.error_code).to eq("PROVIDER_NOT_READY")
        expect(result.error_message).to eq("Waiting for flags configuration")
        expect(result.reason).to eq("ERROR")
        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => false)
      end
    end

    context "when binding evaluator returns error" do
      before do
        allow(evaluator).to receive(:get_assignment).and_return(error)
        engine.reconfigure!(configuration)
      end

      let(:error) do
        Datadog::OpenFeature::ResolutionDetails.new(
          value: "something",
          error_code: "PROVIDER_FATAL",
          error_message: "Ooops",
          reason: "ERROR",
          flag_metadata: {},
          extra_logging: {},
          error?: true,
          log?: false
        )
      end

      it "returns evaluation error and reports exposure" do
        expect(reporter).to receive(:report).with(error, flag_key: "test", context: nil)

        expect(result.value).to eq("something")
        expect(result.error_code).to eq("PROVIDER_FATAL")
        expect(result.error_message).to eq("Ooops")
        expect(result.reason).to eq("ERROR")
        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => false)
      end
    end

    context "when binding evaluator returns a frozen error" do
      before do
        allow(evaluator).to receive(:get_assignment).and_return(error)
        engine.reconfigure!(configuration)
      end

      let(:error) do
        Datadog::OpenFeature::ResolutionDetails.build_error(
          value: "fallback",
          error_code: Datadog::OpenFeature::Ext::PARSE_ERROR,
          error_message: "invalid configuration"
        )
      end

      it "preserves the error and stamps the evaluation metadata" do
        expect(reporter).to receive(:report).with(
          kind_of(Datadog::OpenFeature::ResolutionDetails), flag_key: "test", context: nil
        )

        expect(result.error_code).to eq("PARSE_ERROR")
        expect(result.error_message).to eq("invalid configuration")
        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => false)
      end
    end

    context "when binding evaluator raises error" do
      before do
        allow(telemetry).to receive(:report)
        allow(evaluator).to receive(:get_assignment).and_raise(error)

        engine.reconfigure!(configuration)
      end

      let(:error) { RuntimeError.new("Crash") }

      it "returns evaluation error and does not report exposure" do
        expect(reporter).not_to receive(:report)

        expect(result.value).to eq("fallback")
        expect(result.error_code).to eq("GENERAL")
        expect(result.error_message).to eq("RuntimeError: Crash")
        expect(result.reason).to eq("ERROR")
        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => false)
      end
    end

    context "when the evaluator changes while an error is returned" do
      before do
        allow(telemetry).to receive(:report)
        allow(replacement_evaluator).to receive(:observe_full_evaluation_data).and_return(true)
        allow(Datadog::OpenFeature::NativeEvaluator).to receive(:new).and_return(evaluator, replacement_evaluator)
        allow(evaluator).to receive(:get_assignment) do
          engine.reconfigure!(configuration)
          raise error
        end
        engine.reconfigure!(configuration)
      end

      let(:replacement_evaluator) { instance_double(Datadog::OpenFeature::NativeEvaluator) }
      let(:error) { RuntimeError.new("Crash") }

      it "uses the policy snapshot from the evaluator that performed the evaluation" do
        expect(evaluator).to receive(:observe_full_evaluation_data).once.and_return(false)
        expect(replacement_evaluator).not_to receive(:observe_full_evaluation_data)
        expect(reporter).not_to receive(:report)

        expect(result.error_code).to eq("GENERAL")
        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => false)
      end
    end

    # The in-flight evaluation keeps the policy from the evaluator that performed it;
    # reconfiguration must not replace that snapshot retroactively.
    context "when full evaluation data is disabled while an evaluation is in flight" do
      before do
        allow(telemetry).to receive(:report)
        allow(replacement_evaluator).to receive(:observe_full_evaluation_data).and_return(false)
        allow(Datadog::OpenFeature::NativeEvaluator).to receive(:new).and_return(evaluator, replacement_evaluator)
        allow(evaluator).to receive(:get_assignment) do
          engine.reconfigure!(configuration)
          raise error
        end
        engine.reconfigure!(configuration)
      end

      let(:replacement_evaluator) { instance_double(Datadog::OpenFeature::NativeEvaluator) }
      let(:error) { RuntimeError.new("Crash") }

      it "keeps the enabled policy from the evaluator that performed the evaluation" do
        expect(evaluator).to receive(:observe_full_evaluation_data).once.and_return(true)
        expect(replacement_evaluator).not_to receive(:observe_full_evaluation_data)

        expect(result.error_code).to eq("GENERAL")
        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => true)
      end
    end

    context "when expected type not in the allowed list" do
      before { engine.reconfigure!(configuration) }

      let(:result) { engine.fetch_value("test", default_value: "x", expected_type: :whatever) }

      it "returns evaluation error and does not report exposure" do
        expect(reporter).not_to receive(:report)

        expect(result.value).to eq("x")
        expect(result.error_code).to eq("UNKNOWN_TYPE")
        expect(result.error_message).to start_with("unknown type :whatever, allowed types")
        expect(result.reason).to eq("ERROR")
        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => false)
      end
    end

    context "when binding evaluator returns resolution details" do
      before do
        allow(evaluator).to receive(:get_assignment).and_return(details)

        engine.reconfigure!(configuration)
      end

      let(:evaluation_context) { instance_double("OpenFeature::SDK::EvaluationContext", fields: {"targeting_key" => "joe"}) }
      let(:details) do
        Datadog::OpenFeature::ResolutionDetails.new(
          value: "hello",
          variant: "blue",
          error_code: nil,
          error_message: nil,
          reason: "MATCH",
          flag_metadata: {},
          extra_logging: {},
          error?: true,
          log?: false
        )
      end
      let(:result) do
        engine.fetch_value(
          "test", default_value: "bye!", expected_type: :string, evaluation_context: evaluation_context
        )
      end

      it "returns resolved value and reports exposure" do
        expect(reporter).to receive(:report)
          .with(kind_of(Datadog::OpenFeature::ResolutionDetails), flag_key: "test", context: evaluation_context)

        expect(result.value).to eq("hello")
        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => false)
      end

      it "stamps an enabled policy from the evaluator" do
        allow(evaluator).to receive(:observe_full_evaluation_data).and_return(true)
        expect(reporter).to receive(:report)

        expect(result.flag_metadata).to include(observe_full_evaluation_data_key => true)
      end
    end
  end

  describe "#reconfigure!" do
    context "when configuration is not yet present" do
      it "does nothing and logs the issue" do
        expect(logger).to receive(:debug).with(/OpenFeature: Removing configuration/)

        engine.reconfigure!(nil)
      end
    end

    context "when binding initialization fails with exception" do
      before { allow(Datadog::OpenFeature::NativeEvaluator).to receive(:new).and_raise(error) }

      let(:error) { StandardError.new("Ooops") }

      it "reports error to telemetry and logs it" do
        expect(logger).to receive(:error).with(/Ooops/)
        expect(telemetry).to receive(:report)
          .with(error, description: match(/OpenFeature: Failed to reconfigure/))

        expect { engine.reconfigure!("{}") }.to raise_error(described_class::ReconfigurationError, "StandardError: Ooops")
      end
    end
  end
end
