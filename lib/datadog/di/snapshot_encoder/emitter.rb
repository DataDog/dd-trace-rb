# frozen_string_literal: true

require_relative "array_node"
require_relative "fragment_node"
require_relative "object_node"

module Datadog
  module DI
    module SnapshotEncoder
      # The writer of the JSON text of an encoded tree. The emitter is the
      # only code that writes collection JSON, and it runs after pruning
      # ends.
      #
      # @api private
      class Emitter
        # Writes the JSON text of the tree under +root+. The walk keeps its
        # pending container nodes on an explicit stack.
        #
        # @param root [Node] the root of the encoded tree
        # @return [String] the UTF-8 JSON text, of +root.size+ bytes
        def emit(root)
          output = String.new(capacity: root.size, encoding: ::Encoding::UTF_8)
          stack = []
          append_node(output, stack, root)
          until stack.empty?
            frame = stack.last
            container = frame[0]
            index = frame[1]
            children = container.children
            if index == children.length
              output << ((ObjectNode === container) ? "}" : "]")
              stack.pop
              next
            end

            frame[1] = index + 1
            output << "," if index > 0
            if ObjectNode === container
              output << container.member_names_json.fetch(index) << ":"
            end
            append_node(output, stack, children.fetch(index))
          end
          output
        end

        private

        # Appends a fragment node's text, or the opening bracket of a
        # container node and pushes its frame.
        #
        # @param output [String] the JSON text written so far
        # @param stack [Array<Array(ContainerNode, Integer)>] the pending container nodes and their next child positions
        # @param node [Node] the node to write
        # @return [void]
        def append_node(output, stack, node)
          if FragmentNode === node
            output << node.fragment
          elsif ObjectNode === node
            output << "{"
            stack << [node, 0]
          else
            array = node #: ArrayNode
            output << "["
            stack << [array, 0]
          end
          nil
        end
      end
    end
  end
end
