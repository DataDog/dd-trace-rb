# frozen_string_literal: true

require "datadog/ai_guard/evaluation/result"

RSpec.describe Datadog::AIGuard::Evaluation::Result do
  describe ".new" do
    it "raises Datadog::AIGuard::AIGuardClientError when some key is missing" do
      expect { described_class.new({}) }.to raise_error(
        Datadog::AIGuard::AIGuardClientError,
        "Missing key: \"data\""
      )
    end
  end

  let(:raw_response) do
    {
      "data" => {
        "attributes" => {
          "action" => action,
          "reason" => "Some reason",
          "tags" => ["some", "tags"],
          "is_blocking_enabled" => is_blocking_enabled
        }
      }
    }
  end

  let(:action) { "DENY" }
  let(:is_blocking_enabled) { false }

  describe "#action" do
    it "returns the action from the response body" do
      expect(described_class.new(raw_response).action).to eq(raw_response.dig("data", "attributes", "action"))
    end
  end

  describe "#reason" do
    it "returns the reason from the response body" do
      expect(described_class.new(raw_response).reason).to eq(raw_response.dig("data", "attributes", "reason"))
    end
  end

  describe "#tags" do
    it "returns the tags from the response body" do
      expect(described_class.new(raw_response).tags).to eq(raw_response.dig("data", "attributes", "tags"))
    end
  end

  describe "#blocking_enabled?" do
    it "returns a boolean is_blocking_enabled from the response body" do
      expect(described_class.new(raw_response).blocking_enabled?).to eq(
        raw_response.dig("data", "attributes", "is_blocking_enabled")
      )
    end
  end

  context "when action is ALLOW" do
    let(:action) { "ALLOW" }

    describe "#allow?" do
      it "returns true" do
        expect(described_class.new(raw_response)).to be_allow
      end
    end

    describe "#deny?" do
      it "returns false" do
        expect(described_class.new(raw_response)).not_to be_deny
      end
    end

    describe "#abort?" do
      it "returns false" do
        expect(described_class.new(raw_response)).not_to be_abort
      end
    end
  end

  context "when action is DENY" do
    let(:action) { "DENY" }

    describe "#allow?" do
      it "returns false" do
        expect(described_class.new(raw_response)).not_to be_allow
      end
    end

    describe "#deny?" do
      it "returns true" do
        expect(described_class.new(raw_response)).to be_deny
      end
    end

    describe "#abort?" do
      it "returns false" do
        expect(described_class.new(raw_response)).not_to be_abort
      end
    end
  end

  context "when action is ABORT" do
    let(:action) { "ABORT" }

    describe "#allow?" do
      it "returns false" do
        expect(described_class.new(raw_response)).not_to be_allow
      end
    end

    describe "#deny?" do
      it "returns false" do
        expect(described_class.new(raw_response)).not_to be_deny
      end
    end

    describe "#abort?" do
      it "returns true" do
        expect(described_class.new(raw_response)).to be_abort
      end
    end
  end
end
