# frozen_string_literal: true

require_relative "snapshot_pruner/node"
require_relative "snapshot_pruner/node_queue"
require_relative "snapshot_pruner/parser"

module Datadog
  module DI
    # Reduces an encoded snapshot below a byte limit by replacing captured
    # value objects with the pruned marker, operating directly on the
    # encoded bytes. The largest, most deeply nested captured values are
    # replaced first.
    #
    # @api private
    class SnapshotPruner
      # Replacement for each pruned object.
      PRUNED_MARKER = '{"pruned":true}'

      # Shallowest nesting level that is pruned. The snapshot payload nests
      # +debugger+, +snapshot+, +captures+ and the capture sets above the
      # captured values, which start at level 5 (method probe +arguments+
      # and +locals+ members, line probe line objects). Applying the level
      # to promoted parents as well keeps +captures+ and the capture sets.
      MIN_LEVEL = 5

      # Initializes the pruner.
      #
      # @return [void]
      def initialize
        @parser = Parser.new
      end

      # The parser that builds the object tree of an encoded snapshot.
      # @return [Parser]
      attr_reader :parser

      # Prunes an encoded snapshot that exceeds +max_size+.
      #
      # @param json [String] the encoded snapshot, a JSON object
      # @param max_size [Integer] the size limit in bytes
      # @return [String] +json+ itself when it is within +max_size+ or has
      #   no object that can be pruned; otherwise a copy with the selected
      #   objects replaced by PRUNED_MARKER, which exceeds +max_size+ only
      #   when pruning every candidate cannot cover the excess
      # @raise [ArgumentError] when the document is malformed
      def prune(json, max_size:)
        excess = json.bytesize - max_size
        return json if excess <= 0

        root = parser.parse(json)
        selected_nodes = select_nodes(root, excess)
        return json if selected_nodes.empty?

        rewrite(json, selected_nodes)
      end

      private

      # Selects the objects to replace, highest priority first, until their
      # replacement saves more than +excess+ bytes or no candidate is left.
      #
      # An object no larger than PRUNED_MARKER, such as an empty Hash, is
      # kept, because replacing it would grow the snapshot; it
      # still counts as pruned toward its parent's promotion, so that the
      # parent can be replaced whole.
      #
      # @param root [Node] the root object of the snapshot
      # @param excess [Integer] bytes the snapshot exceeds the limit by
      # @return [Array<Node>] non-overlapping selected objects in document order
      def select_nodes(root, excess)
        queue = NodeQueue.new
        root.each_leaf do |leaf|
          queue.push(leaf) if leaf.level >= MIN_LEVEL
        end

        selected = {}
        saving = 0
        while (node = queue.pop)
          node_saving = replacement_saving(node)
          if node_saving > 0
            selected[node.start_offset] = node
            saving += node_saving
            break if saving > excess
          end

          parent = node.parent
          next unless parent && parent.level >= MIN_LEVEL
          parent.record_pruned_child
          next unless parent.all_children_pruned?

          parent.promote
          queue.push(parent)
          parent.children.each do |child|
            saving -= replacement_saving(child) if selected.delete(child.start_offset)
          end
        end

        selected.values.sort_by!(&:start_offset)
      end

      # Returns the bytes saved by replacing an object with PRUNED_MARKER.
      #
      # @param node [Node] the object to replace
      # @return [Integer] the saving, zero or negative for an object no
      #   larger than PRUNED_MARKER
      def replacement_saving(node)
        node.size - PRUNED_MARKER.bytesize
      end

      # Copies +json+ with each selected object replaced by PRUNED_MARKER.
      #
      # @param json [String] the encoded snapshot
      # @param selected_nodes [Array<Node>] non-overlapping objects in document order
      # @return [String] the pruned snapshot
      def rewrite(json, selected_nodes)
        pruned = String.new(capacity: json.bytesize, encoding: json.encoding)
        offset = 0
        selected_nodes.each do |node|
          kept = json.byteslice(offset, node.start_offset - offset) #: String
          pruned << kept << PRUNED_MARKER
          offset = node.end_offset
        end
        tail = json.byteslice(offset, json.bytesize - offset) #: String
        pruned << tail
      end
    end
  end
end
