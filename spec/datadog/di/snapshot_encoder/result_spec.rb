require "datadog/di/spec_helper"
require "datadog/di/snapshot_encoder"

RSpec.describe Datadog::DI::SnapshotEncoder::Result do
  subject(:result) do
    described_class.new(encoded: encoded, pruned: pruned, bytes: 2_000_000,
      replaced_primitives: 3, cut_collections: 2, replaced_collections: 1)
  end

  let(:encoded) { "{}" }
  let(:pruned) { true }

  it "exposes the outcome of one encoding" do
    expect(result.encoded).to eq "{}"
    expect(result.pruned?).to be true
    expect(result.bytes).to eq 2_000_000
    expect(result.replaced_primitives).to eq 3
    expect(result.cut_collections).to eq 2
    expect(result.replaced_collections).to eq 1
  end

  context "for a dropped payload" do
    let(:encoded) { nil }
    let(:pruned) { false }

    it "has no JSON text and is not pruned" do
      expect(result.encoded).to be nil
      expect(result.pruned?).to be false
    end
  end
end
