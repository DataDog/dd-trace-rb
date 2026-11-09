# frozen_string_literal: true

require "spec_helper"
require "securerandom"
require "datadog/open_feature/split_features"

RSpec.describe Datadog::OpenFeature::SplitFeatures do
  let(:logger) { instance_double(Datadog::Core::Logger, warn: nil) }

  before do
    allow(Datadog).to receive(:logger).and_return(logger)
    described_class.send(:reset_warned_destinations_for_tests)
  end

  after { described_class.send(:reset_warned_destinations_for_tests) }

  describe ".write" do
    subject(:metadata) { described_class.write({"existing" => 1}, features) }

    context "with one feature per destination" do
      let(:features) do
        [
          ["holdout.key", "h-1", ["HOOK"]],
          ["holdout.share", 0.25, ["EXPOSURE"]],
          ["holdout.enabled", false, ["EVALUATION"]],
        ]
      end

      it "writes each feature under its destination prefix only" do
        expect(metadata).to eq(
          "existing" => 1,
          "__dd_feature.holdout.key" => "h-1",
          "__dd_exposure_feature.holdout.share" => 0.25,
          "__dd_evaluation_feature.holdout.enabled" => false,
        )
      end
    end

    context "with a feature routed to several destinations" do
      let(:features) { [["holdout.key", "h-1", ["HOOK", "EXPOSURE", "EVALUATION"]]] }

      it "writes one entry per destination" do
        expect(metadata).to eq(
          "existing" => 1,
          "__dd_feature.holdout.key" => "h-1",
          "__dd_exposure_feature.holdout.key" => "h-1",
          "__dd_evaluation_feature.holdout.key" => "h-1",
        )
      end
    end

    context "with unknown destinations" do
      let(:unknown) { "UNKNOWN_#{SecureRandom.hex(4)}" }
      let(:features) { [["holdout.key", "h-1", [unknown, "hook"]], ["holdout.group", "g", ["HOOK", unknown]]] }

      it "ignores them, so a feature with only unknown destinations goes nowhere" do
        expect(metadata).to eq("existing" => 1, "__dd_feature.holdout.group" => "g")
      end

      it "warns once for each distinct unknown value" do
        metadata
        described_class.write({}, features)

        expect(logger).to have_received(:warn).with(/unknown split feature destination #{unknown.inspect}/).once
      end
    end

    context "when the logger raises while warning" do
      let(:features) { [["holdout.key", "h-1", ["HOOK", "UNKNOWN_#{SecureRandom.hex(4)}"]]] }

      before { allow(logger).to receive(:warn).and_raise("logger failure") }

      it "still writes the known destinations" do
        expect(metadata).to eq("existing" => 1, "__dd_feature.holdout.key" => "h-1")
      end
    end

    context "when more unknown destinations arrive than the warning cap" do
      let(:features) do
        Array.new(described_class::MAX_WARNED_DESTINATIONS + 1) { |index| ["key", "v", ["CAP_#{SecureRandom.hex(4)}_#{index}"]] }
      end

      it "stops warning instead of remembering every value" do
        metadata

        expect(logger).to have_received(:warn).exactly(described_class::MAX_WARNED_DESTINATIONS).times
      end
    end
  end

  describe ".read" do
    let(:metadata) do
      {
        "__dd_feature.holdout.key" => "h-1",
        "__dd_feature.holdout.share" => 0.25,
        "__dd_exposure_feature.holdout.key" => "exposure-only",
        "__dd_allocation_key" => "allocation",
      }
    end

    it "returns the features of one prefix keyed without it" do
      expect(described_class.read(metadata, "__dd_feature.")).to eq("holdout.key" => "h-1", "holdout.share" => 0.25)
    end

    it "returns a frozen hash" do
      expect(described_class.read(metadata, "__dd_feature.")).to be_frozen
    end

    it "returns the shared empty hash when nothing matches" do
      expect(described_class.read(metadata, "__dd_evaluation_feature.")).to be(described_class::EMPTY)
    end

    it "returns the shared empty hash without metadata" do
      expect(described_class.read(nil, "__dd_feature.")).to be(described_class::EMPTY)
    end
  end
end
