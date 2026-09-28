# frozen_string_literal: true

require "datadog/ai_guard/redaction/result"

RSpec.describe Datadog::AIGuard::Redaction::Result do
  subject(:result) do
    described_class.new(
      [],
      applied_count: state.fetch(:applied_count),
      failures_count: state.fetch(:failures_count),
      performed: state.fetch(:performed)
    )
  end

  context "when redaction is skipped" do
    let(:state) { {applied_count: 0, failures_count: 0, performed: false} }

    it { expect(result).not_to be_performed }
    it { expect(result).not_to be_redacted }
  end

  context "when redaction is performed without applying a replacement" do
    let(:state) { {applied_count: 0, failures_count: 1, performed: true} }

    it { expect(result).to be_performed }
    it { expect(result).not_to be_redacted }
  end

  context "when redaction applies a replacement" do
    let(:state) { {applied_count: 1, failures_count: 0, performed: true} }

    it { expect(result).to be_performed }
    it { expect(result).to be_redacted }
  end
end
