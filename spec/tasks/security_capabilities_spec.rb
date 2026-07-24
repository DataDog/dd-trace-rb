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

  describe ".audit_eligible_lockfiles" do
    it "includes underscore appraisal variants for 3.1+ and excludes 3.0 and below" do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "ruby_3.1_contrib.gemfile.lock"))
        FileUtils.touch(File.join(dir, "ruby_4.0_contrib.gemfile.lock"))
        FileUtils.touch(File.join(dir, "ruby_3.0_contrib.gemfile.lock"))
        FileUtils.touch(File.join(dir, "ruby_2.5_contrib.gemfile.lock"))

        result = described_class.audit_eligible_lockfiles(dir).map { |p| File.basename(p) }

        expect(result).to include("ruby_3.1_contrib.gemfile.lock", "ruby_4.0_contrib.gemfile.lock")
        expect(result).not_to include("ruby_3.0_contrib.gemfile.lock", "ruby_2.5_contrib.gemfile.lock")
      end
    end

    it "includes dash base lockfiles for 3.1+ and excludes 3.0 base" do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, "ruby-3.1.gemfile.lock"))
        FileUtils.touch(File.join(dir, "ruby-4.0.gemfile.lock"))
        FileUtils.touch(File.join(dir, "ruby-3.0.gemfile.lock"))

        result = described_class.audit_eligible_lockfiles(dir).map { |p| File.basename(p) }

        expect(result).to include("ruby-3.1.gemfile.lock", "ruby-4.0.gemfile.lock")
        expect(result).not_to include("ruby-3.0.gemfile.lock")
      end
    end
  end
end
