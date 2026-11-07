require "datadog/di/spec_helper"
require "datadog/di/snapshot_pruner/node"

RSpec.describe Datadog::DI::SnapshotPruner::Node do
  di_test

  def node(start_offset: 0, end_offset: 10, level: 5, parent: nil)
    described_class.new(start_offset: start_offset, level: level, parent: parent).tap do |created|
      created.close(end_offset)
    end
  end

  describe "#initialize" do
    subject(:open_node) { described_class.new(start_offset: 7, level: 2, parent: nil) }

    it "starts open, unflagged and without children" do
      expect(open_node.start_offset).to eq 7
      expect(open_node.end_offset).to eq 7
      expect(open_node.level).to eq 2
      expect(open_node.parent).to be_nil
      expect(open_node.children).to eq []
      expect(open_node.pruned_child_count).to eq 0
      expect(open_node.not_captured?).to be false
      expect(open_node.not_captured_depth?).to be false
    end
  end

  describe "#close" do
    it "sets the end offset and the size" do
      created = described_class.new(start_offset: 3, level: 0, parent: nil)
      created.close(20)

      expect(created.end_offset).to eq 20
      expect(created.size).to eq 17
    end
  end

  describe "#add_child" do
    it "appends the child and makes the node a branch" do
      parent = node
      child = node(parent: parent)

      expect(parent.leaf?).to be true
      parent.add_child(child)

      expect(parent.children).to eq [child]
      expect(parent.leaf?).to be false
      expect(child.parent).to be parent
    end
  end

  describe "#mark_not_captured" do
    it "sets the not-captured flag only" do
      flagged = node
      flagged.mark_not_captured

      expect(flagged.not_captured?).to be true
      expect(flagged.not_captured_depth?).to be false
    end
  end

  describe "#mark_not_captured_depth" do
    it "sets the depth flag only" do
      flagged = node
      flagged.mark_not_captured_depth

      expect(flagged.not_captured_depth?).to be true
      expect(flagged.not_captured?).to be false
    end
  end

  describe "#record_pruned_child" do
    it "records one resolved child at a time" do
      parent = node
      2.times { parent.add_child(node(parent: parent)) }

      parent.record_pruned_child

      expect(parent.pruned_child_count).to eq 1
    end
  end

  describe "#all_children_pruned?" do
    it "returns true once every child is recorded" do
      parent = node
      2.times { parent.add_child(node(parent: parent)) }

      expect(parent.all_children_pruned?).to be false
      parent.record_pruned_child
      expect(parent.all_children_pruned?).to be false
      parent.record_pruned_child
      expect(parent.all_children_pruned?).to be true
    end
  end

  describe "#promote" do
    it "sets both flags" do
      promoted = node
      promoted.promote

      expect(promoted.not_captured?).to be true
      expect(promoted.not_captured_depth?).to be true
    end
  end

  describe "#priority" do
    it "ranks the depth flag above level, not-captured flag and size" do
      depth = node(level: 5, end_offset: 2)
      depth.mark_not_captured_depth
      deep_large = node(level: 9, end_offset: 1_000_000)
      deep_large.mark_not_captured

      expect(depth.priority).to be > deep_large.priority
    end

    it "ranks level above the not-captured flag and size" do
      deep = node(level: 7, end_offset: 2)
      shallow = node(level: 6, end_offset: 1_000_000)
      shallow.mark_not_captured

      expect(deep.priority).to be > shallow.priority
    end

    it "ranks the not-captured flag above size" do
      flagged = node(end_offset: 2)
      flagged.mark_not_captured
      large = node(end_offset: 1_000_000)

      expect(flagged.priority).to be > large.priority
    end

    it "ranks a larger object above a smaller one when the other fields are equal" do
      expect(node(end_offset: 101).priority).to be > node(end_offset: 100).priority
    end

    it "stays a fixed-size Integer for the largest supported fields" do
      largest = node(level: (1 << 17) - 1, end_offset: (1 << 43) - 1)
      largest.promote

      expect(largest.priority).to be < (1 << 62)
    end
  end

  describe "#each_leaf" do
    it "yields every leaf of the subtree" do
      root = node(level: 0)
      branch = node(level: 1, parent: root)
      leaf_a = node(level: 2, parent: branch)
      leaf_b = node(level: 2, parent: branch)
      leaf_c = node(level: 1, parent: root)
      root.add_child(branch)
      root.add_child(leaf_c)
      branch.add_child(leaf_a)
      branch.add_child(leaf_b)

      leaves = []
      root.each_leaf { |leaf| leaves << leaf }

      expect(leaves).to contain_exactly(leaf_a, leaf_b, leaf_c)
    end

    it "yields the node itself when it is a leaf" do
      single = node
      leaves = []
      single.each_leaf { |leaf| leaves << leaf }

      expect(leaves).to eq [single]
    end
  end
end
