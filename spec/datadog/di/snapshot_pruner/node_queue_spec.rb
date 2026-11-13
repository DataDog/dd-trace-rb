require "datadog/di/spec_helper"
require "datadog/di/snapshot_pruner/node"
require "datadog/di/snapshot_pruner/node_queue"

RSpec.describe Datadog::DI::SnapshotPruner::NodeQueue do
  di_test

  subject(:queue) { described_class.new }

  def node(level:, size:)
    Datadog::DI::SnapshotPruner::Node.new(start_offset: 0, level: level, parent: nil).tap do |created|
      created.close(size)
    end
  end

  describe "#pop" do
    it "returns nil when the queue is empty" do
      expect(queue.pop).to be_nil
    end

    it "returns the nodes in descending priority order" do
      nodes = [
        node(level: 5, size: 30),
        node(level: 7, size: 10),
        node(level: 6, size: 500),
        node(level: 7, size: 20),
        node(level: 5, size: 40),
      ]
      nodes.each { |each_node| queue.push(each_node) }

      popped = Array.new(nodes.size) { queue.pop }

      expect(popped.map(&:priority)).to eq nodes.map(&:priority).sort.reverse
      expect(queue.pop).to be_nil
    end

    it "orders pushes made between pops" do
      queue.push(node(level: 5, size: 10))
      queue.push(node(level: 6, size: 10))
      expect(queue.pop.level).to eq 6

      promoted = node(level: 5, size: 50)
      promoted.promote
      queue.push(promoted)
      queue.push(node(level: 9, size: 10))

      expect(queue.pop).to be promoted
      expect(queue.pop.level).to eq 9
      expect(queue.pop.level).to eq 5
      expect(queue.pop).to be_nil
    end

    it "orders many nodes" do
      nodes = Array.new(200) { |i| node(level: 5 + i % 4, size: (i * 7919) % 1_000 + 1) }
      nodes.each { |each_node| queue.push(each_node) }

      popped = []
      while (each_node = queue.pop)
        popped << each_node.priority
      end

      expect(popped).to eq nodes.map(&:priority).sort.reverse
    end
  end

  describe "#size" do
    it "counts the queued nodes" do
      expect(queue.size).to eq 0
      queue.push(node(level: 5, size: 10))
      queue.push(node(level: 5, size: 20))
      expect(queue.size).to eq 2
      queue.pop
      expect(queue.size).to eq 1
    end
  end
end
