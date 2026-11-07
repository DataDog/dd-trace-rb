# frozen_string_literal: true

module Datadog
  module DI
    module SnapshotEncoder
      # The outcome of encoding one snapshot payload: the JSON text, or nil
      # for a dropped payload, with the unpruned size and the number of
      # changes each prune step made.
      #
      # @api private
      class Result
        # Initializes the outcome.
        #
        # @param encoded [String, nil] the JSON text, or nil when the payload is dropped
        # @param pruned [Boolean] whether a prune step changed the payload and the payload fits the cap
        # @param bytes [Integer] the exact encoded size of the payload before pruning
        # @param replaced_primitives [Integer] the number of primitives step 1 replaced
        # @param cut_collections [Integer] the number of collections step 2 cut
        # @param replaced_collections [Integer] the number of collections step 3 replaced
        def initialize(encoded:, pruned:, bytes:, replaced_primitives:, cut_collections:, replaced_collections:)
          @encoded = encoded
          @pruned = pruned
          @bytes = bytes
          @replaced_primitives = replaced_primitives
          @cut_collections = cut_collections
          @replaced_collections = replaced_collections
        end

        # The JSON text, or nil when the payload is dropped.
        # @return [String, nil]
        attr_reader :encoded

        # The exact encoded size of the payload before pruning.
        # @return [Integer]
        attr_reader :bytes

        # The number of primitives step 1 replaced.
        # @return [Integer]
        attr_reader :replaced_primitives

        # The number of collections step 2 cut.
        # @return [Integer]
        attr_reader :cut_collections

        # The number of collections step 3 replaced.
        # @return [Integer]
        attr_reader :replaced_collections

        # Whether a prune step changed the payload and the encoded size is
        # at most the cap.
        #
        # @return [Boolean]
        def pruned?
          pruned
        end

        private

        # Whether a prune step changed the payload and the encoded size is
        # at most the cap.
        # @return [Boolean]
        attr_reader :pruned
      end
    end
  end
end
