# frozen_string_literal: true

require_relative "container_node"

module Datadog
  module DI
    module SnapshotEncoder
      # A container node that encodes a JSON array.
      #
      # @api private
      class ArrayNode < ContainerNode
        # Adds an element at build time.
        #
        # @param node [Node] the element, whose subtree is complete
        # @return [void]
        def add_element(node)
          add_child(node, node.size)
        end

        # Removes every element after the first +kept_count+ and updates
        # the sizes of this node and its ancestors.
        #
        # @param kept_count [Integer] the number of elements kept; must be +KEPT_ELEMENT_COUNT+
        # @return [void]
        # @raise [ArgumentError] when +kept_count+ is not +KEPT_ELEMENT_COUNT+
        def truncate_elements(kept_count)
          truncate_children(kept_count)
        end
      end
    end
  end
end
