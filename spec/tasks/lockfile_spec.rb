require "spec_helper"
require "tmpdir"
require_relative "../../tasks/lockfile"

RSpec.describe Lockfile do
  describe "#initialize" do
    it "rejects paths without the .gemfile.lock suffix" do
      expect { described_class.new("gemfiles/ruby-3.1_contrib.gemfile") }
        .to raise_error(ArgumentError, /Lockfile path must end with \.gemfile\.lock/)
    end
  end

  describe "#audit_eligible?" do
    it "is true for underscore appraisal variants on 3.1+ and false on 3.0 and below" do
      expect(described_class.new("ruby_3.1_contrib.gemfile.lock").audit_eligible?).to eq(true)
      expect(described_class.new("ruby_4.0_contrib.gemfile.lock").audit_eligible?).to eq(true)
      expect(described_class.new("ruby_3.0_contrib.gemfile.lock").audit_eligible?).to eq(false)
      expect(described_class.new("ruby_2.5_contrib.gemfile.lock").audit_eligible?).to eq(false)
    end

    it "is true for dash base lockfiles on 3.1+ and false on 3.0" do
      expect(described_class.new("ruby-3.1.gemfile.lock").audit_eligible?).to eq(true)
      expect(described_class.new("ruby-4.0.gemfile.lock").audit_eligible?).to eq(true)
      expect(described_class.new("ruby-3.0.gemfile.lock").audit_eligible?).to eq(false)
    end
  end

  describe "#checksum_eligible?" do
    it "is true for 3.1+ and false for 3.0 and below" do
      expect(described_class.new("ruby_3.1_contrib.gemfile.lock").checksum_eligible?).to eq(true)
      expect(described_class.new("ruby-4.0.gemfile.lock").checksum_eligible?).to eq(true)
      expect(described_class.new("ruby_3.0_contrib.gemfile.lock").checksum_eligible?).to eq(false)
      expect(described_class.new("ruby-2.5.gemfile.lock").checksum_eligible?).to eq(false)
    end
  end

  describe "#gemfile_path" do
    it "strips the .lock suffix from the path" do
      expect(described_class.new("gemfiles/ruby_3.1_contrib.gemfile.lock").gemfile_path)
        .to eq("gemfiles/ruby_3.1_contrib.gemfile")
    end
  end

  describe "#orphaned?" do
    it "is true when the companion gemfile is absent" do
      Dir.mktmpdir do |dir|
        lockfile = described_class.new(File.join(dir, "ruby-3.1_contrib.gemfile.lock"))

        expect(lockfile).to be_orphaned
      end
    end

    it "is false when the companion gemfile exists" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "ruby-3.1_contrib.gemfile"), "")
        lockfile = described_class.new(File.join(dir, "ruby-3.1_contrib.gemfile.lock"))

        expect(lockfile).not_to be_orphaned
      end
    end
  end

  describe ".orphaned_lockfile_paths" do
    it "returns the sorted paths of lockfiles with no companion gemfile" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "ruby-3.1_contrib.gemfile"), "")
        File.write(File.join(dir, "ruby-3.1_contrib.gemfile.lock"), "")
        File.write(File.join(dir, "ruby-3.2_contrib.gemfile.lock"), "")
        File.write(File.join(dir, "ruby-3.3_contrib.gemfile.lock"), "")

        expect(described_class.orphaned_lockfile_paths(dir)).to eq([
          File.join(dir, "ruby-3.2_contrib.gemfile.lock"),
          File.join(dir, "ruby-3.3_contrib.gemfile.lock"),
        ])
      end
    end
  end

  describe "#has_checksums_section?" do
    let(:fixtures) { "spec/fixtures/checksum_coverage" }

    it "is true for a lockfile with a CHECKSUMS section" do
      expect(described_class.new("#{fixtures}/ruby-3.1_eligible_with_checksums.gemfile.lock").has_checksums_section?).to eq(true)
    end

    it "is false for a lockfile without a CHECKSUMS section" do
      expect(described_class.new("#{fixtures}/ruby-3.1_eligible_without_checksums.gemfile.lock").has_checksums_section?).to eq(false)
    end
  end
end
