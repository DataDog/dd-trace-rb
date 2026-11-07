# frozen_string_literal: true

module Datadog
  module DI
    module SnapshotEncoder
      # A node of the encoded tree that SnapshotEncoder builds from a
      # snapshot payload. A node knows the exact byte size of its JSON
      # encoding and its position in its parent node.
      #
      # @api private
      class Node
        # Initializes a detached node.
        #
        # @param size [Integer] the byte size of the node's JSON encoding
        def initialize(size)
          @size = size
          @parent = nil
          @parent_index = nil
        end

        # The byte size of the node's JSON encoding.
        # @return [Integer]
        attr_reader :size

        # The container node holding this node, or nil for the root and
        # for a detached node.
        # @return [ContainerNode, nil]
        attr_reader :parent

        # The node's member or element position in its parent.
        # @return [Integer, nil]
        attr_reader :parent_index

        protected

        # Sets the node's parent link and its position in the parent.
        #
        # @param parent [ContainerNode] the container node holding this node
        # @param parent_index [Integer] the node's position in +parent+
        # @return [void]
        def attach(parent, parent_index)
          @parent = parent
          @parent_index = parent_index
          nil
        end
      end
    end
  end
end
