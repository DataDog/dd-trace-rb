# frozen_string_literal: true

require_relative "node"

module Datadog
  module DI
    module SnapshotEncoder
      # A node of the encoded tree that encodes a JSON object or array.
      # A container node keeps the exact byte size of its encoding and of
      # the encoding it would have with only its first
      # +KEPT_ELEMENT_COUNT+ children, and keeps both sizes exact when a
      # child is replaced, appended or removed.
      #
      # @api private
      class ContainerNode < Node
        # The byte size of an empty JSON object or array: its brackets.
        EMPTY_SIZE = 2

        # Initializes an empty container node.
        def initialize
          super(EMPTY_SIZE)
          @prefix_size = EMPTY_SIZE
          @children = []
        end

        # The byte size the node's encoding has with only its first
        # +KEPT_ELEMENT_COUNT+ children.
        # @return [Integer]
        attr_reader :prefix_size

        # The child nodes, in encoding order. Read-only: the node's
        # methods are the only writers.
        # @return [Array<Node>]
        attr_reader :children

        # Replaces the child at +index+ with +node+ and updates the sizes
        # of this node and its ancestors.
        #
        # @param index [Integer] the position of the child to replace
        # @param node [Node] the replacement child
        # @return [void]
        def replace_child(index, node)
          replaced = children.fetch(index)
          node.attach(self, index)
          children[index] = node
          apply_child_delta(index, node.size - replaced.size)
        end

        # Adds +delta+ to the size of this node and of each ancestor, and
        # to the prefix size of each of them that received the delta
        # through one of its first +KEPT_ELEMENT_COUNT+ children.
        #
        # @param child_index [Integer] the position of the changed child in this node
        # @param delta [Integer] the byte size change of the child
        # @return [void]
        def apply_child_delta(child_index, delta)
          node = self
          index = child_index
          while node
            node.add_size_delta(index, delta)
            index = node.parent_index
            node = node.parent
          end
          nil
        end

        protected

        # Adds +delta+ to this node's size, and to its prefix size when
        # the delta comes from one of its first +KEPT_ELEMENT_COUNT+
        # children.
        #
        # @param child_index [Integer] the position of the changed child
        # @param delta [Integer] the byte size change of the child
        # @return [void]
        def add_size_delta(child_index, delta)
          @size = size + delta
          @prefix_size = prefix_size + delta if child_index < KEPT_ELEMENT_COUNT
          nil
        end

        private

        # Adds a child at build time. The ancestors are built after this
        # node, so only this node's sizes change.
        #
        # @param node [Node] the child, whose subtree is complete
        # @param contribution [Integer] the byte size the child adds, without its separating comma
        # @return [void]
        def add_child(node, contribution)
          index = children.length
          node.attach(self, index)
          children << node
          contribution += 1 if index > 0
          @size = size + contribution
          @prefix_size = prefix_size + contribution if index < KEPT_ELEMENT_COUNT
          nil
        end

        # Appends a child after the tree is built and updates the sizes of
        # this node and its ancestors.
        #
        # @param node [Node] the appended child
        # @param contribution [Integer] the byte size the child adds, without its separating comma
        # @return [void]
        def append_child(node, contribution)
          index = children.length
          node.attach(self, index)
          children << node
          contribution += 1 if index > 0
          apply_child_delta(index, contribution)
        end

        # Removes every child after the first +kept_count+ and updates the
        # sizes of this node and its ancestors from the recorded prefix
        # size.
        #
        # @param kept_count [Integer] the number of children kept; must be +KEPT_ELEMENT_COUNT+
        # @return [void]
        # @raise [ArgumentError] when +kept_count+ is not +KEPT_ELEMENT_COUNT+
        def truncate_children(kept_count)
          unless kept_count == KEPT_ELEMENT_COUNT
            raise ArgumentError, "kept_count must be #{KEPT_ELEMENT_COUNT}, the length the prefix size is recorded for: #{kept_count}"
          end
          return if children.length <= kept_count

          delta = prefix_size - size
          children.slice!(kept_count, children.length - kept_count)
          @size = prefix_size
          container = parent
          index = parent_index
          container.apply_child_delta(index, delta) if container && index
          nil
        end
      end
    end
  end
end
