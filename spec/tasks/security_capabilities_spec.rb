require "spec_helper"
require_relative "../../tasks/security_capabilities"

RSpec.describe SecurityCapabilities do
  describe ".for_version" do
    it "grants no features to legacy Rubies (2.5-3.0)" do
      %w[2.5 2.6 2.7 3.0].each do |v|
        expect(described_class.for_version(v)).to eq(audit: false, checksum: false, cooldown: false)
      end
    end

    it "grants audit and checksum but not cooldown on 3.1" do
      expect(described_class.for_version("3.1")).to eq(audit: true, checksum: true, cooldown: false)
    end

    it "grants all features on 3.2 and above" do
      %w[3.2 3.3 3.4 4.0].each do |v|
        expect(described_class.for_version(v)).to eq(audit: true, checksum: true, cooldown: true)
      end
    end

    it "treats an unknown future version as fully capable" do
      expect(described_class.for_version("4.1")).to eq(audit: true, checksum: true, cooldown: true)
    end
  end
end
