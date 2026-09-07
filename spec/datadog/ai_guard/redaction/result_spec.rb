# frozen_string_literal: true

require "datadog/ai_guard/redaction/result"

RSpec.describe Datadog::AIGuard::Redaction::Result do
  subject(:result) do
    described_class.new(
      [],
      applied: state.fetch(:applied),
      failures: state.fetch(:failures),
      performed: state.fetch(:performed)
    )
  end

  context "when redaction is skipped" do
    let(:state) { {applied: 0, failures: 0, performed: false} }

    it { expect(result).not_to be_performed }
    it { expect(result).not_to be_redacted }
  end

  context "when redaction is performed without applying a replacement" do
    let(:state) { {applied: 0, failures: 1, performed: true} }

    it { expect(result).to be_performed }
    it { expect(result).not_to be_redacted }
  end

  context "when redaction applies a replacement" do
    let(:state) { {applied: 1, failures: 0, performed: true} }

    it { expect(result).to be_performed }
    it { expect(result).to be_redacted }
  end
end
