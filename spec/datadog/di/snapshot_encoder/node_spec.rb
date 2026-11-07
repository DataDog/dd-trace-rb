require "datadog/di/spec_helper"
require "datadog/di/snapshot_encoder"

RSpec.describe Datadog::DI::SnapshotEncoder::Node do
  subject(:node) { described_class.new(7) }

  it "records its size and starts detached" do
    expect(node.size).to eq 7
    expect(node.parent).to be nil
    expect(node.parent_index).to be nil
  end

  it "keeps attach out of the public interface" do
    expect(node).not_to respond_to(:attach)
  end

  context "when a container node adds it" do
    let(:container) { Datadog::DI::SnapshotEncoder::ArrayNode.new }

    it "links the node to the container at its position" do
      container.add_element(Datadog::DI::SnapshotEncoder::FragmentNode.new("1"))
      container.add_element(node)

      expect(node.parent).to equal container
      expect(node.parent_index).to eq 1
    end
  end
end
