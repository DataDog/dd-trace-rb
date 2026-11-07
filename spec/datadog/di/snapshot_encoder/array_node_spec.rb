require "datadog/di/spec_helper"
require_relative "../snapshot_encoder_helpers"

RSpec.describe Datadog::DI::SnapshotEncoder::ArrayNode do
  include SnapshotEncoderHelpers

  subject(:node) { described_class.new }

  def fragment(text)
    Datadog::DI::SnapshotEncoder::FragmentNode.new(text)
  end

  it "has the size of an empty array" do
    expect(node.size).to eq 2
    expect(node.prefix_size).to eq 2
    expect(emit(node)).to eq "[]"
  end

  describe "#add_element" do
    it "adds each element and its separating comma to the size" do
      node.add_element(fragment("1"))
      expect(node.size).to eq "[1]".bytesize
      node.add_element(fragment("22"))
      expect(node.size).to eq "[1,22]".bytesize
      expect(emit(node)).to eq "[1,22]"
    end

    it "adds only the first 20 elements to the prefix size" do
      25.times { |i| node.add_element(fragment(i.to_s)) }

      expect(node.size).to eq JSON.dump((0...25).to_a).bytesize
      expect(node.prefix_size).to eq JSON.dump((0...20).to_a).bytesize
    end
  end

  describe "#truncate_elements" do
    let(:parent) { described_class.new }

    before do
      parent.add_element(fragment("0"))
      25.times { |i| node.add_element(fragment(i.to_s)) }
      parent.add_element(node)
    end

    it "keeps the first 20 elements and updates the sizes of the node and its parent" do
      node.truncate_elements(20)

      expect(emit(node)).to eq JSON.dump((0...20).to_a)
      expect(node.size).to eq emit(node).bytesize
      expect(node.prefix_size).to eq node.size
      expect(parent.size).to eq emit(parent).bytesize
    end

    it "truncates a node without a parent" do
      root = described_class.new
      25.times { |i| root.add_element(fragment(i.to_s)) }

      root.truncate_elements(20)

      expect(emit(root)).to eq JSON.dump((0...20).to_a)
      expect(root.size).to eq emit(root).bytesize
    end

    it "changes nothing when the node has at most 20 elements" do
      short = described_class.new
      20.times { |i| short.add_element(fragment(i.to_s)) }

      expect { short.truncate_elements(20) }.not_to change { emit(short) }
      expect(short.size).to eq emit(short).bytesize
    end

    it "raises ArgumentError for a kept count other than 20" do
      expect { node.truncate_elements(10) }
        .to raise_error(ArgumentError, "kept_count must be 20, the length the prefix size is recorded for: 10")
      expect(node.children.length).to eq 25
    end
  end
end
