require "datadog/di/spec_helper"
require_relative "../snapshot_encoder_helpers"

RSpec.describe Datadog::DI::SnapshotEncoder::ObjectNode do
  include SnapshotEncoderHelpers

  subject(:node) { described_class.new }

  def fragment(text)
    Datadog::DI::SnapshotEncoder::FragmentNode.new(text)
  end

  def add(target, name, text)
    target.add_member(name, JSON.dump(name), fragment(text))
  end

  it "has the size of an empty object" do
    expect(node.size).to eq 2
    expect(node.prefix_size).to eq 2
    expect(emit(node)).to eq "{}"
  end

  describe "#add_member" do
    it "records the member name, its encoding and the exact size" do
      add(node, "a", "1")
      add(node, "b\u00e9", "\"x\"")

      expect(node.member_names).to eq ["a", "b\u00e9"]
      expect(node.member_names_json).to eq ["\"a\"", "\"b\u00e9\""]
      expect(emit(node)).to eq "{\"a\":1,\"b\u00e9\":\"x\"}"
      expect(node.size).to eq emit(node).bytesize
    end

    it "adds only the first 20 members to the prefix size" do
      25.times { |i| add(node, "k#{i}", i.to_s) }

      expect(node.size).to eq JSON.dump((0...25).map { |i| ["k#{i}", i] }.to_h).bytesize
      expect(node.prefix_size).to eq JSON.dump((0...20).map { |i| ["k#{i}", i] }.to_h).bytesize
    end
  end

  describe "#append_member" do
    let(:root) { described_class.new }

    before do
      3.times { |i| add(node, "k#{i}", i.to_s) }
      add(root, "first", "0")
      root.add_member("inner", "\"inner\"", node)
    end

    it "appends the member after the last one and updates every ancestor" do
      node.append_member("notCapturedReason", "\"notCapturedReason\"", fragment("\"payloadTooLarge\""))

      expect(emit(node)).to eq "{\"k0\":0,\"k1\":1,\"k2\":2,\"notCapturedReason\":\"payloadTooLarge\"}"
      expect_exact_sizes(root)
    end

    it "appends to an empty object without a comma" do
      empty = described_class.new
      empty.append_member("size", "\"size\"", fragment("3"))

      expect(emit(empty)).to eq "{\"size\":3}"
      expect(empty.size).to eq 10
      expect(empty.prefix_size).to eq 10
    end

    it "leaves the prefix size of a node with 20 members unchanged" do
      wide = described_class.new
      20.times { |i| add(wide, "k#{i}", i.to_s) }

      expect { wide.append_member("size", "\"size\"", fragment("3")) }.not_to change(wide, :prefix_size)
      expect(wide.size).to eq emit(wide).bytesize
    end
  end

  describe "#replace_child" do
    it "replaces the member value and keeps the sizes exact below and above position 20" do
      root = described_class.new
      25.times { |i| add(node, "k#{i}", "\"#{"v" * i}\"") }
      root.add_member("inner", "\"inner\"", node)

      node.replace_child(3, fragment("{\"pruned\":true}"))
      node.replace_child(22, fragment("{\"pruned\":true}"))

      expect(JSON.parse(emit(node)).values_at("k3", "k22")).to eq [{"pruned" => true}, {"pruned" => true}]
      expect(node.children[3].parent_index).to eq 3
      expect_exact_sizes(root)
    end
  end

  describe "#truncate_members" do
    it "keeps the first 20 members with their names and updates the ancestors" do
      root = described_class.new
      25.times { |i| add(node, "k#{i}", i.to_s) }
      root.add_member("inner", "\"inner\"", node)

      node.truncate_members(20)

      expect(node.member_names).to eq (0...20).map { |i| "k#{i}" }
      expect(node.member_names_json.length).to eq 20
      expect_exact_sizes(root)
    end

    it "raises ArgumentError for a kept count other than 20" do
      expect { node.truncate_members(21) }.to raise_error(ArgumentError, /kept_count must be 20/)
    end
  end
end
