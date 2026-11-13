# frozen_string_literal: true

module Datadog
  module DI
    class SnapshotPruner
      # Priority queue of snapshot objects that yields the object with the
      # greatest pruning priority first, implemented as a binary max-heap
      # over an Array.
      #
      # @api private
      class NodeQueue
        # Initializes an empty queue.
        #
        # @return [void]
        def initialize
          @heap = []
        end

        # Adds an object to the queue.
        #
        # @param node [Node] the object to add
        # @return [void]
        def push(node)
          heap << node
          sift_up(heap.size - 1)
          nil
        end

        # Removes the object with the greatest priority.
        #
        # @return [Node, nil] the removed object, nil when the queue is empty
        def pop
          last = heap.pop
          return last if last.nil? || heap.empty?

          top = heap.first
          heap[0] = last
          sift_down(0)
          top
        end

        # Returns the number of queued objects.
        #
        # @return [Integer]
        def size
          heap.size
        end

        private

        # The heap-ordered queued objects.
        # @return [Array<Node>]
        attr_reader :heap

        # Moves the object at +index+ toward the root until its parent has
        # an equal or greater priority.
        #
        # @param index [Integer] heap position of the object to move
        # @return [void]
        def sift_up(index)
          node = heap[index]
          priority = node.priority
          while index > 0
            parent_index = (index - 1) / 2
            parent = heap[parent_index]
            break if parent.priority >= priority

            heap[index] = parent
            index = parent_index
          end
          heap[index] = node
          nil
        end

        # Moves the object at +index+ toward the leaves until every child
        # has an equal or lower priority.
        #
        # @param index [Integer] heap position of the object to move
        # @return [void]
        def sift_down(index)
          node = heap[index]
          priority = node.priority
          count = heap.size
          loop do
            child_index = 2 * index + 1
            break if child_index >= count

            right_index = child_index + 1
            if right_index < count && heap[right_index].priority > heap[child_index].priority
              child_index = right_index
            end
            child = heap[child_index]
            break if child.priority <= priority

            heap[index] = child
            index = child_index
          end
          heap[index] = node
          nil
        end
      end
    end
  end
end
