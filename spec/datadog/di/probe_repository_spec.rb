require "datadog/di/spec_helper"
require "datadog/di/probe_repository"

RSpec.describe Datadog::DI::ProbeRepository do
  di_test

  let(:repository) { described_class.new }

  let(:probe) do
    instance_double(Datadog::DI::Probe, id: "test-probe-id")
  end

  let(:probe2) do
    instance_double(Datadog::DI::Probe, id: "test-probe-id-2")
  end

  describe "#installed_probes" do
    context "when empty" do
      it "returns empty hash" do
        expect(repository.installed_probes).to eq({})
      end
    end

    context "with probes" do
      before do
        repository.add_installed(probe)
      end

      it "returns hash with probes" do
        expect(repository.installed_probes).to eq("test-probe-id" => probe)
      end
    end
  end

  describe "#find_installed" do
    context "when probe exists" do
      before do
        repository.add_installed(probe)
      end

      it "returns the probe" do
        expect(repository.find_installed("test-probe-id")).to eq(probe)
      end
    end

    context "when probe does not exist" do
      it "returns nil" do
        expect(repository.find_installed("nonexistent")).to be_nil
      end
    end
  end

  describe "#add_installed" do
    it "adds probe to installed collection" do
      repository.add_installed(probe)
      expect(repository.installed_probes["test-probe-id"]).to eq(probe)
    end
  end

  describe "#remove_installed" do
    before do
      repository.add_installed(probe)
    end

    it "removes and returns the probe" do
      result = repository.remove_installed("test-probe-id")
      expect(result).to eq(probe)
      expect(repository.installed_probes).to be_empty
    end

    context "when probe does not exist" do
      it "returns nil" do
        expect(repository.remove_installed("nonexistent")).to be_nil
      end
    end
  end

  describe "#pending_probes" do
    context "when empty" do
      it "returns empty hash" do
        expect(repository.pending_probes).to eq({})
      end
    end
  end

  describe "#find_pending" do
    context "when probe exists" do
      before do
        repository.add_pending(probe)
      end

      it "returns the probe" do
        expect(repository.find_pending("test-probe-id")).to eq(probe)
      end
    end

    context "when probe does not exist" do
      it "returns nil" do
        expect(repository.find_pending("nonexistent")).to be_nil
      end
    end
  end

  describe "#add_pending" do
    it "adds probe to pending collection" do
      repository.add_pending(probe)
      expect(repository.pending_probes["test-probe-id"]).to eq(probe)
    end
  end

  describe "#remove_pending" do
    before do
      repository.add_pending(probe)
    end

    it "removes and returns the probe" do
      result = repository.remove_pending("test-probe-id")
      expect(result).to eq(probe)
      expect(repository.pending_probes).to be_empty
    end
  end

  describe "#clear_pending" do
    before do
      repository.add_pending(probe)
      repository.add_pending(probe2)
    end

    it "clears all pending probes" do
      repository.clear_pending
      expect(repository.pending_probes).to be_empty
    end
  end

  describe "#failed_probes" do
    context "when empty" do
      it "returns empty hash" do
        expect(repository.failed_probes).to eq({})
      end
    end

    context "with failures" do
      before do
        repository.add_failed("test-probe-id", "Error message")
      end

      it "returns hash with error messages" do
        expect(repository.failed_probes).to eq("test-probe-id" => "Error message")
      end
    end
  end

  describe "#find_failed" do
    context "when failure exists" do
      before do
        repository.add_failed("test-probe-id", "Error message")
      end

      it "returns the error message" do
        expect(repository.find_failed("test-probe-id")).to eq("Error message")
      end
    end

    context "when failure does not exist" do
      it "returns nil" do
        expect(repository.find_failed("nonexistent")).to be_nil
      end
    end
  end

  describe "#add_failed" do
    it "adds failure to failed collection" do
      repository.add_failed("test-probe-id", "Error message")
      expect(repository.failed_probes["test-probe-id"]).to eq("Error message")
    end
  end

  describe "#remove_failed" do
    before do
      repository.add_failed("test-probe-id", "Error message")
    end

    it "removes and returns the error message" do
      result = repository.remove_failed("test-probe-id")
      expect(result).to eq("Error message")
      expect(repository.failed_probes).to be_empty
    end
  end

  describe "#clear_all" do
    before do
      repository.add_installed(probe)
      repository.add_installed(probe2)
      repository.add_pending(probe)
      repository.add_failed("failed-probe", "Error")
    end

    it "clears all collections" do
      repository.clear_all
      expect(repository.installed_probes).to be_empty
      expect(repository.pending_probes).to be_empty
      expect(repository.failed_probes).to be_empty
    end

    context "with block" do
      it "yields each installed probe" do
        yielded_probes = []
        repository.clear_all do |p|
          yielded_probes << p
        end

        expect(yielded_probes).to contain_exactly(probe, probe2)
      end

      it "clears collections before yielding" do
        repository.clear_all do |_p|
          # During yield, collections should already be cleared
          expect(repository.installed_probes).to be_empty
        end
      end
    end

    context "without block" do
      it "does not raise" do
        expect { repository.clear_all }.not_to raise_error
      end
    end
  end
end
