# frozen_string_literal: true

require_relative "node"

module Datadog
  module DI
    module SnapshotEncoder
      # A leaf node of the encoded tree holding complete JSON text: an
      # encoded primitive, an encoded envelope scalar, or a marker.
      #
      # @api private
      class FragmentNode < Node
        # Initializes the node with its JSON text.
        #
        # @param fragment [String] the JSON text of the node
        def initialize(fragment)
          super(fragment.bytesize)
          @fragment = fragment
        end

        # The JSON text of the node.
        # @return [String]
        attr_reader :fragment
      end
    end
  end
end
