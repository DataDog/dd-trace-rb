# frozen_string_literal: true

require_relative "container_node"

module Datadog
  module DI
    module SnapshotEncoder
      # A container node that encodes a JSON object. Each member keeps its
      # name and the JSON encoding of the name.
      #
      # @api private
      class ObjectNode < ContainerNode
        # The byte size of the colon between a member name and its value.
        NAME_SEPARATOR_SIZE = 1

        # Initializes an object node without members.
        def initialize
          super
          @member_names = []
          @member_names_json = []
        end

        # The member names, in encoding order. Read-only: the node's
        # methods are the only writers.
        # @return [Array<String>]
        attr_reader :member_names

        # The JSON encodings of the member names, in encoding order.
        # Read-only: the node's methods are the only writers.
        # @return [Array<String>]
        attr_reader :member_names_json

        # Adds a member at build time.
        #
        # @param name [String] the member name
        # @param name_json [String] the JSON encoding of +name+
        # @param node [Node] the member value, whose subtree is complete
        # @return [void]
        def add_member(name, name_json, node)
          member_names << name
          member_names_json << name_json
          add_child(node, name_json.bytesize + NAME_SEPARATOR_SIZE + node.size)
        end

        # Appends a member after the tree is built and updates the sizes
        # of this node and its ancestors.
        #
        # @param name [String] the member name
        # @param name_json [String] the JSON encoding of +name+
        # @param node [Node] the member value
        # @return [void]
        def append_member(name, name_json, node)
          member_names << name
          member_names_json << name_json
          append_child(node, name_json.bytesize + NAME_SEPARATOR_SIZE + node.size)
        end

        # Removes every member after the first +kept_count+ and updates the
        # sizes of this node and its ancestors.
        #
        # @param kept_count [Integer] the number of members kept; must be +KEPT_ELEMENT_COUNT+
        # @return [void]
        # @raise [ArgumentError] when +kept_count+ is not +KEPT_ELEMENT_COUNT+
        def truncate_members(kept_count)
          truncate_children(kept_count)
          member_names.slice!(kept_count, member_names.length)
          member_names_json.slice!(kept_count, member_names_json.length)
          nil
        end
      end
    end
  end
end
