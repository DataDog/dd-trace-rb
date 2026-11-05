# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "datadog/open_feature/exposures/event"

RSpec.describe Datadog::OpenFeature::Exposures::Event do
  before { allow(Datadog::Core::Utils::Time).to receive(:now).and_return(now) }

  let(:now) { Time.utc(2025, 1, 1, 0, 0, 0) }
  let(:event) { described_class.build(result, flag_key: "feature_flag", context: context) }
  let(:serial_id) { nil }
  let(:context) do
    instance_double(
      OpenFeature::SDK::EvaluationContext, targeting_key: "john-doe", fields: {"targeting_key" => "john-doe"},
    )
  end
  let(:result) do
    Datadog::OpenFeature::ResolutionDetails.new(
      value: 4,
      allocation_key: "4-for-john-doe",
      variant: "4",
      serial_id: serial_id,
      flag_metadata: {
        "allocationKey" => "4-for-john-doe",
        "variationType" => "number",
        "doLog" => true,
      },
      log?: true,
      error?: false,
    )
  end

  describe ".build" do
    context "when context contains nested fields" do
      let(:context) do
        instance_double(
          OpenFeature::SDK::EvaluationContext,
          targeting_key: "john-doe",
          fields: {
            "targeting_key" => "john-doe",
            "age" => 21,
            "active" => true,
            "ratio" => 7.5,
            "nickname" => "johnny",
            "ignored_hash" => {foo: "bar"},
            "ignored_array" => [1, 2],
          },
        )
      end
      let(:expected) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: "4-for-john-doe"},
          flag: {key: "feature_flag"},
          variant: {key: "4"},
          subject: {
            id: "john-doe",
            attributes: {"age" => 21, "active" => true, "ratio" => 7.5, "nickname" => "johnny"},
          },
        }
      end

      it "builds exposure event and dropps nested fields" do
        expect(event).to eq(expected)
      end
    end

    context "when context does not contain extra fields" do
      let(:context) do
        instance_double(
          OpenFeature::SDK::EvaluationContext, targeting_key: "john-doe", fields: {"targeting_key" => "john-doe"},
        )
      end
      let(:expected) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: "4-for-john-doe"},
          flag: {key: "feature_flag"},
          variant: {key: "4"},
          subject: {id: "john-doe", attributes: {}},
        }
      end

      it { expect(event).to eq(expected) }
    end

    context "when result has a serial id" do
      let(:serial_id) { 7 }
      let(:expected) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: "4-for-john-doe"},
          flag: {key: "feature_flag"},
          variant: {key: "4"},
          subject: {id: "john-doe", attributes: {}},
          serial_id: 7,
        }
      end

      it { expect(event).to eq(expected) }
    end

    context "when result has a serial id of zero" do
      let(:serial_id) { 0 }
      let(:expected) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: "4-for-john-doe"},
          flag: {key: "feature_flag"},
          variant: {key: "4"},
          subject: {id: "john-doe", attributes: {}},
          serial_id: 0,
        }
      end

      it { expect(event).to eq(expected) }
    end
  end

  describe ".build with split features" do
    let(:result) do
      Datadog::OpenFeature::ResolutionDetails.new(
        value: 4, allocation_key: "4-for-john-doe", variant: "4", flag_metadata: {}, log?: true, error?: false,
        features: features,
      )
    end

    context "when the split has EXPOSURE features" do
      let(:features) do
        [
          ["holdout.key", "h-1", ["EXPOSURE"]],
          ["holdout.share", 0.25, ["HOOK", "EXPOSURE"]],
          ["hook.only", true, ["HOOK"]],
        ]
      end

      it "adds only them, as a flat features object" do
        expect(event[:features]).to eq("holdout.key" => "h-1", "holdout.share" => 0.25)
      end
    end

    context "when the split has no EXPOSURE features" do
      let(:features) { [["hook.only", true, ["HOOK"]]] }

      it "omits the features object" do
        expect(event).not_to have_key(:features)
      end
    end

    context "when the split has no features" do
      let(:features) { [] }

      it "omits the features object" do
        expect(event).not_to have_key(:features)
      end
    end
  end

  describe ".cache_key" do
    let(:context) { instance_double(OpenFeature::SDK::EvaluationContext, targeting_key: "john-doe") }

    it "returns cache key based on flag and targeting key" do
      expect(described_class.cache_key(result, flag_key: "feature_flag", context: context))
        .to eq("feature_flag:john-doe")
    end
  end

  describe ".cache_value" do
    let(:context) { instance_double(OpenFeature::SDK::EvaluationContext, targeting_key: "john-doe") }

    it "returns cache value based on allocation and variant" do
      expect(described_class.cache_value(result, flag_key: "feature_flag", context: context))
        .to eq("4-for-john-doe:4:")
    end

    context "when result has a serial id" do
      let(:serial_id) { 7 }

      it "returns cache value based on allocation, variant and serial id" do
        expect(described_class.cache_value(result, flag_key: "feature_flag", context: context))
          .to eq("4-for-john-doe:4:7")
      end
    end

    context "when result has a serial id of zero" do
      let(:serial_id) { 0 }

      it "returns a value that differs from the value without a serial id" do
        expect(described_class.cache_value(result, flag_key: "feature_flag", context: context))
          .to eq("4-for-john-doe:4:0")
      end
    end
  end
end
