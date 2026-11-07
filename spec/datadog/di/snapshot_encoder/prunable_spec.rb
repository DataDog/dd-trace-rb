require "datadog/di/spec_helper"
require "datadog/di/snapshot_encoder"

RSpec.describe Datadog::DI::SnapshotEncoder::Prunable do
  subject(:prunable) do
    described_class.new(
      node: node, parent: parent, index: 4, kind: described_class::KIND_COLLECTION,
      depth: 2, ordinal: 10, last_ordinal: 40, element_member: "elements",
      element_container: element_container, element_count: 30, cut_start_ordinal: 31,
      not_captured_reason: "collectionSize", reason_member_index: 2, size_member_index: 3,
    )
  end

  let(:node) { Datadog::DI::SnapshotEncoder::ObjectNode.new }
  let(:parent) { Datadog::DI::SnapshotEncoder::ArrayNode.new }
  let(:element_container) { Datadog::DI::SnapshotEncoder::ArrayNode.new }

  it "exposes its registration data" do
    expect(prunable.node).to equal node
    expect(prunable.parent).to equal parent
    expect(prunable.index).to eq 4
    expect(prunable.kind).to eq :collection
    expect(prunable.depth).to eq 2
    expect(prunable.ordinal).to eq 10
    expect(prunable.last_ordinal).to eq 40
    expect(prunable.element_member).to eq "elements"
    expect(prunable.element_container).to equal element_container
    expect(prunable.element_count).to eq 30
    expect(prunable.cut_start_ordinal).to eq 31
    expect(prunable.not_captured_reason).to eq "collectionSize"
    expect(prunable.reason_member_index).to eq 2
    expect(prunable.size_member_index).to eq 3
  end

  it "names the two kinds" do
    expect(described_class::KIND_PRIMITIVE).to eq :primitive
    expect(described_class::KIND_COLLECTION).to eq :collection
  end
end
