# frozen_string_literal: true

require "datadog/ai_guard/component"

RSpec.describe Datadog::AIGuard::Evaluation::Outcome do
  describe "#block?" do
    let(:outcome) do
      described_class.new(
        result: result,
        redaction: redaction,
        blocking_enabled: decision.fetch(:blocking_enabled)
      )
    end
    let(:result) do
      instance_double(
        Datadog::AIGuard::Evaluation::Result,
        deny?: decision.fetch(:deny),
        abort?: decision.fetch(:abort)
      )
    end
    let(:redaction) { instance_double(Datadog::AIGuard::Redaction::Result) }

    context "when action is ALLOW and blocking is enabled" do
      let(:decision) { {blocking_enabled: true, deny: false, abort: false} }

      it { expect(outcome).not_to be_block }
    end

    context "when action is ALLOW and blocking is disabled" do
      let(:decision) { {blocking_enabled: false, deny: false, abort: false} }

      it { expect(outcome).not_to be_block }
    end

    context "when action is DENY and blocking is enabled" do
      let(:decision) { {blocking_enabled: true, deny: true, abort: false} }

      it { expect(outcome).to be_block }
    end

    context "when action is DENY and blocking is disabled" do
      let(:decision) { {blocking_enabled: false, deny: true, abort: false} }

      it { expect(outcome).not_to be_block }
    end

    context "when action is ABORT and blocking is enabled" do
      let(:decision) { {blocking_enabled: true, deny: false, abort: true} }

      it { expect(outcome).to be_block }
    end

    context "when action is ABORT and blocking is disabled" do
      let(:decision) { {blocking_enabled: false, deny: false, abort: true} }

      it { expect(outcome).not_to be_block }
    end
  end
end
