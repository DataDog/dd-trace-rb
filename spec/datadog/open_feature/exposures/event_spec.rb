# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "datadog/open_feature/exposures/event"

RSpec.describe Datadog::OpenFeature::Exposures::Event do
  before { allow(Datadog::Core::Utils::Time).to receive(:now).and_return(now) }

  let(:now) { Time.utc(2025, 1, 1, 0, 0, 0) }
  let(:event) do
    described_class.build(
      flag_key: "feature_flag", allocation_key: "4-for-john-doe", variant: "4", serial_id: serial_id,
      context: context, features: features,
    )
  end
  let(:serial_id) { nil }
  let(:context) do
    instance_double(
      OpenFeature::SDK::EvaluationContext, targeting_key: "john-doe", fields: {"targeting_key" => "john-doe"},
    )
  end
  let(:features) { {} }

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

    context "when exposure features are present" do
      let(:features) { {"holdout.key" => "h-1", "holdout.share" => 0.25, "holdout.enabled" => false} }

      it "adds them as a flat features object" do
        expect(event).to include(
          features: {"holdout.key" => "h-1", "holdout.share" => 0.25, "holdout.enabled" => false},
        )
      end
    end

    context "when there are no exposure features" do
      it "omits the features object" do
        expect(event).not_to have_key(:features)
      end
    end
  end

  describe ".cache_key" do
    it "returns cache key based on flag and targeting key" do
      expect(described_class.cache_key(flag_key: "feature_flag", targeting_key: "john-doe"))
        .to eq("feature_flag:john-doe")
    end
  end

  describe ".cache_value" do
    subject(:cache_value) do
      described_class.cache_value(allocation_key: "4-for-john-doe", variant: "4", serial_id: serial_id)
    end

    it "returns cache value based on allocation and variant" do
      expect(cache_value).to eq("4-for-john-doe:4:")
    end

    context "when result has a serial id" do
      let(:serial_id) { 7 }

      it "returns cache value based on allocation, variant and serial id" do
        expect(cache_value).to eq("4-for-john-doe:4:7")
      end
    end

    context "when result has a serial id of zero" do
      let(:serial_id) { 0 }

      it "returns a value that differs from the value without a serial id" do
        expect(cache_value).to eq("4-for-john-doe:4:0")
      end
    end
  end
end
