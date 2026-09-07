# frozen_string_literal: true

require "datadog/ai_guard/evaluation/result"

RSpec.describe Datadog::AIGuard::Evaluation::Result do
  subject(:result) do
    described_class.new(
      messages,
      action: attributes.fetch(:action),
      reason: attributes.fetch(:reason),
      tags: attributes.fetch(:tags),
      sds_findings: attributes.fetch(:sds_findings),
      tag_probabilities: attributes.fetch(:tag_probabilities)
    )
  end

  let(:messages) do
    [
      Datadog::AIGuard::Evaluation::Message.new(role: :user, content: "Hello there"),
    ]
  end
  let(:attributes) do
    {
      action: "ALLOW",
      reason: "Some reason",
      tags: ["some", "tags"],
      sds_findings: [{"rule_tag" => "credit_card"}],
      tag_probabilities: {"some" => 0.95, "tags" => 0.1},
    }
  end

  describe "#messages" do
    it { expect(result.messages).to equal(messages) }
  end

  describe "#action" do
    it { expect(result.action).to eq("ALLOW") }
  end

  describe "#reason" do
    it { expect(result.reason).to eq("Some reason") }
  end

  describe "#tags" do
    it { expect(result.tags).to eq(["some", "tags"]) }
  end

  describe "#sds_findings" do
    it { expect(result.sds_findings).to eq([{"rule_tag" => "credit_card"}]) }
  end

  describe "#tag_probabilities" do
    it { expect(result.tag_probabilities).to eq("some" => 0.95, "tags" => 0.1) }
  end

  context "when action is ALLOW" do
    describe "#allow?" do
      it { expect(result).to be_allow }
    end

    describe "#deny?" do
      it { expect(result).not_to be_deny }
    end

    describe "#abort?" do
      it { expect(result).not_to be_abort }
    end
  end

  context "when action is DENY" do
    let(:attributes) do
      {
        action: "DENY",
        reason: "Some reason",
        tags: ["some", "tags"],
        sds_findings: [{"rule_tag" => "credit_card"}],
        tag_probabilities: {"some" => 0.95, "tags" => 0.1},
      }
    end

    describe "#allow?" do
      it { expect(result).not_to be_allow }
    end

    describe "#deny?" do
      it { expect(result).to be_deny }
    end

    describe "#abort?" do
      it { expect(result).not_to be_abort }
    end
  end

  context "when action is ABORT" do
    let(:attributes) do
      {
        action: "ABORT",
        reason: "Some reason",
        tags: ["some", "tags"],
        sds_findings: [{"rule_tag" => "credit_card"}],
        tag_probabilities: {"some" => 0.95, "tags" => 0.1},
      }
    end

    describe "#allow?" do
      it { expect(result).not_to be_allow }
    end

    describe "#deny?" do
      it { expect(result).not_to be_deny }
    end

    describe "#abort?" do
      it { expect(result).to be_abort }
    end
  end
end
