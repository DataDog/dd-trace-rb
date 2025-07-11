require "datadog/profiling/spec_helper"
require "datadog/profiling/sequence_tracker"

RSpec.describe Datadog::Profiling::SequenceTracker do
  describe ".get_next" do
    subject(:get_next) { described_class.get_next }

    before do
      # Reset the sequence number before each test to ensure clean state
      described_class.send(:reset!)
    end

    it "increments the sequence on every call" do
      expect(described_class.get_next).to eq(0)
      expect(described_class.get_next).to eq(1)
      expect(described_class.get_next).to eq(2)
    end

    context "when called after a fork" do
      before { skip("Spec requires Ruby VM supporting fork") unless PlatformHelpers.supports_fork? }

      it "resets the sequence number to 0 in the forked process" do
        expect(described_class.get_next).to eq(0)
        expect(described_class.get_next).to eq(1)

        expect_in_fork do
          expect(described_class.get_next).to eq(0)
          expect(described_class.get_next).to eq(1)
        end
      end

      it "continues incrementing in the parent process after fork" do
        expect(described_class.get_next).to eq(0)
        expect(described_class.get_next).to eq(1)

        expect_in_fork do
          expect(described_class.get_next).to eq(0)
          expect(described_class.get_next).to eq(1)
        end

        expect(described_class.get_next).to eq(2)
        expect(described_class.get_next).to eq(3)
      end
    end
  end

  describe ".reset!" do
    it "is private" do
      expect(described_class.private_methods).to include(:reset!)
    end
  end
end
