# frozen_string_literal: true

require "datadog/ai_guard/redaction"
require "datadog/ai_guard/redaction/result"

RSpec.describe Datadog::AIGuard::Redaction do
  describe ".skipped" do
    subject(:result) { described_class.skipped(messages) }

    let(:messages) { [Object.new] }

    it "returns the original messages without performing redaction" do
      aggregate_failures "skipped redaction result" do
        expect(result.messages).to equal(messages)
        expect(result.applied).to eq(0)
        expect(result.failures).to eq(0)
        expect(result).not_to be_performed
        expect(result).not_to be_redacted
      end
    end
  end
end
