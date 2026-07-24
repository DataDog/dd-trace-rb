require "spec_helper"
require_relative "../../tasks/lockfile"

RSpec.describe Lockfile do
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
end
