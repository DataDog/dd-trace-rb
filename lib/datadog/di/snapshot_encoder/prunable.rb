# frozen_string_literal: true

module Datadog
  module DI
    module SnapshotEncoder
      # A primitive or collection of the captured data that the pruner can
      # replace or cut, with the position, ordering and marker data the
      # prune steps read.
      #
      # @api private
      class Prunable
        # Kind of a captured value without element members.
        KIND_PRIMITIVE = :primitive
        # Kind of a value collection, variable map or capture set.
        KIND_COLLECTION = :collection

        # Initializes the record once the value's subtree is built.
        #
        # @param node [Node] the value's node
        # @param parent [ContainerNode] the node holding +node+
        # @param index [Integer] the position of +node+ in +parent+
        # @param kind [Symbol] +KIND_PRIMITIVE+ or +KIND_COLLECTION+
        # @param depth [Integer] the number of collections enclosing the value
        # @param ordinal [Integer] the value's position in document order
        # @param last_ordinal [Integer] the greatest ordinal inside the value, or +ordinal+ when none is
        # @param element_member [String, nil] the element member name of a value collection
        # @param element_container [ContainerNode, nil] the node holding the elements
        # @param element_count [Integer] the number of elements
        # @param cut_start_ordinal [Integer, nil] the first ordinal of element 21, for a value collection or variable map over 20 elements
        # @param not_captured_reason [String, nil] the +to_s+ of a value collection's +notCapturedReason+ member
        # @param reason_member_index [Integer, nil] the position of the +notCapturedReason+ member in +node+
        # @param size_member_index [Integer, nil] the position of the +size+ member in +node+
        def initialize(node:, parent:, index:, kind:, depth:, ordinal:,
          last_ordinal:, element_member:, element_container:, element_count:,
          cut_start_ordinal:, not_captured_reason:, reason_member_index:,
          size_member_index:)
          @node = node
          @parent = parent
          @index = index
          @kind = kind
          @depth = depth
          @ordinal = ordinal
          @last_ordinal = last_ordinal
          @element_member = element_member
          @element_container = element_container
          @element_count = element_count
          @cut_start_ordinal = cut_start_ordinal
          @not_captured_reason = not_captured_reason
          @reason_member_index = reason_member_index
          @size_member_index = size_member_index
        end

        # The value's node: a FragmentNode for a primitive, an ObjectNode
        # for a collection.
        # @return [Node]
        attr_reader :node

        # The node holding the value's node.
        # @return [ContainerNode]
        attr_reader :parent

        # The position of the value's node in its parent.
        # @return [Integer]
        attr_reader :index

        # The kind of the value: +KIND_PRIMITIVE+ or +KIND_COLLECTION+.
        # @return [Symbol]
        attr_reader :kind

        # The number of collections enclosing the value.
        # @return [Integer]
        attr_reader :depth

        # The value's position in document order.
        # @return [Integer]
        attr_reader :ordinal

        # The greatest ordinal inside the value, or the value's own ordinal
        # when it holds no captured value.
        # @return [Integer]
        attr_reader :last_ordinal

        # The element member name of a value collection: +fields+,
        # +elements+, +entries+ or +stacktrace+; nil for a variable map,
        # a capture set and a primitive.
        # @return [String, nil]
        attr_reader :element_member

        # The node holding the elements: the element member's value for a
        # value collection, +node+ for a variable map, nil for a capture
        # set and a primitive.
        # @return [ContainerNode, nil]
        attr_reader :element_container

        # The number of elements; 0 for a primitive.
        # @return [Integer]
        attr_reader :element_count

        # The first ordinal of element 21 (for a pair, the ordinal of its
        # first member); nil for a collection of 20 elements or fewer, a
        # capture set and a primitive.
        # @return [Integer, nil]
        attr_reader :cut_start_ordinal

        # The +to_s+ of a value collection's +notCapturedReason+ member,
        # or nil when the member is absent.
        # @return [String, nil]
        attr_reader :not_captured_reason

        # The position of the +notCapturedReason+ member in +node+, or nil
        # when the member is absent.
        # @return [Integer, nil]
        attr_reader :reason_member_index

        # The position of the +size+ member in +node+, or nil when the
        # member is absent.
        # @return [Integer, nil]
        attr_reader :size_member_index
      end
    end
  end
end
