require "spec_helper"
require_relative "../../tasks/checksum_coverage"

RSpec.describe ChecksumScanning do
  let(:fixtures) { "spec/fixtures/checksum_coverage" }

  describe ".findings" do
    it "passes an eligible lockfile that has checksums" do
      result = described_class.findings(["#{fixtures}/ruby-3.1_eligible_with_checksums.gemfile.lock"])

      expect(result).to be_empty
    end

    it "flags an eligible lockfile missing checksums" do
      result = described_class.findings(["#{fixtures}/ruby-3.1_eligible_without_checksums.gemfile.lock"])

      expect(result).to eq(
        [{lockfile: "#{fixtures}/ruby-3.1_eligible_without_checksums.gemfile.lock", problem: :missing_checksums}],
      )
    end

    it "passes a legacy lockfile that has no checksums" do
      result = described_class.findings(["#{fixtures}/ruby-3.0_legacy_without_checksums.gemfile.lock"])

      expect(result).to be_empty
    end

    it "flags a legacy lockfile that unexpectedly has checksums" do
      result = described_class.findings(["#{fixtures}/ruby-3.0_legacy_with_checksums.gemfile.lock"])

      expect(result).to eq(
        [{lockfile: "#{fixtures}/ruby-3.0_legacy_with_checksums.gemfile.lock", problem: :unexpected_checksums}],
      )
    end

    it "scans multiple lockfiles and reports all findings" do
      result = described_class.findings(
        [
          "#{fixtures}/ruby-3.1_eligible_with_checksums.gemfile.lock",
          "#{fixtures}/ruby-3.1_eligible_without_checksums.gemfile.lock",
          "#{fixtures}/ruby-3.0_legacy_without_checksums.gemfile.lock",
          "#{fixtures}/ruby-3.0_legacy_with_checksums.gemfile.lock",
        ],
      )

      expect(result).to contain_exactly(
        {lockfile: "#{fixtures}/ruby-3.1_eligible_without_checksums.gemfile.lock", problem: :missing_checksums},
        {lockfile: "#{fixtures}/ruby-3.0_legacy_with_checksums.gemfile.lock", problem: :unexpected_checksums},
      )
    end
  end
end
