# frozen_string_literal: true

module Datadog
  module DI
    class SnapshotPruner
      # A JSON object of an encoded snapshot: its byte range, its nesting
      # level, its parent and child objects, and the flags that rank it for
      # pruning.
      #
      # @api private
      class Node
        # Bit of the packed priority set for an object truncated for depth.
        NOT_CAPTURED_DEPTH_BIT = 1 << 61

        # Shift of the level within the packed priority.
        LEVEL_SHIFT = 44

        # Bit of the packed priority set for an object carrying a
        # +notCapturedReason+.
        NOT_CAPTURED_BIT = 1 << 43

        # Initializes an open object whose closing brace has not been read.
        #
        # @param start_offset [Integer] byte offset of the object's opening brace
        # @param level [Integer] nesting level, 0 for the root object
        # @param parent [Node, nil] the enclosing object, nil for the root object
        # @return [void]
        def initialize(start_offset:, level:, parent:)
          @start_offset = start_offset
          @end_offset = start_offset
          @level = level
          @parent = parent
          @children = []
          @pruned_child_count = 0
          @not_captured = false
          @not_captured_depth = false
        end

        # The byte offset of the object's opening brace.
        # @return [Integer]
        attr_reader :start_offset

        # The byte offset just after the object's closing brace.
        # @return [Integer]
        attr_reader :end_offset

        # The nesting level of the object, 0 for the root object.
        # @return [Integer]
        attr_reader :level

        # The enclosing object, nil for the root object.
        # @return [Node, nil]
        attr_reader :parent

        # The objects nested directly in this object.
        # @return [Array<Node>]
        attr_reader :children

        # The number of children selected for pruning.
        # @return [Integer]
        attr_reader :pruned_child_count

        # Whether the object carries a +notCapturedReason+ member.
        # @return [Boolean]
        attr_reader :not_captured
        alias_method :not_captured?, :not_captured

        # Whether the object's +notCapturedReason+ is +depth+, or the object
        # was promoted to a pruning candidate.
        # @return [Boolean]
        attr_reader :not_captured_depth
        alias_method :not_captured_depth?, :not_captured_depth

        # Returns the encoded size of the object.
        #
        # @return [Integer] bytes from the opening brace through the closing brace
        def size
          end_offset - start_offset
        end

        # Returns whether the object contains no nested objects.
        #
        # @return [Boolean]
        def leaf?
          children.empty?
        end

        # Packs the pruning sort key (depth flag, level, not-captured flag,
        # size) into one Integer, so that ranking two objects is one Integer
        # comparison. The fields fit below 2**62 for levels below 2**17 and
        # sizes below 2**43 bytes.
        #
        # @return [Integer] a greater value for an object to prune earlier
        def priority
          (not_captured_depth? ? NOT_CAPTURED_DEPTH_BIT : 0) |
            (level << LEVEL_SHIFT) |
            (not_captured? ? NOT_CAPTURED_BIT : 0) |
            size
        end

        # Appends a directly nested object.
        #
        # @param child [Node] the nested object
        # @return [void]
        def add_child(child)
          children << child
          nil
        end

        # Records the position of the object's closing brace.
        #
        # @param end_offset [Integer] byte offset just after the closing brace
        # @return [void]
        def close(end_offset)
          @end_offset = end_offset
          nil
        end

        # Flags the object as carrying a +notCapturedReason+ member.
        #
        # @return [void]
        def mark_not_captured
          @not_captured = true
          nil
        end

        # Flags the object as truncated for depth.
        #
        # @return [void]
        def mark_not_captured_depth
          @not_captured_depth = true
          nil
        end

        # Counts one child selected for pruning.
        #
        # @return [Boolean] whether every child is now selected
        def count_pruned_child
          @pruned_child_count = pruned_child_count + 1
          pruned_child_count >= children.size
        end

        # Turns the object, whose children are all selected, into a
        # pruning candidate that ranks ahead of every object without the
        # depth flag.
        #
        # @return [void]
        def promote
          mark_not_captured
          mark_not_captured_depth
        end

        # Yields every object of the subtree that contains no nested objects.
        #
        # @yieldparam leaf [Node] an object without nested objects
        # @return [void]
        def each_leaf
          pending = [self] #: Array[Node]
          while (node = pending.pop)
            if node.leaf?
              yield node
            else
              pending.concat(node.children)
            end
          end
          nil
        end
      end
    end
  end
end
