# frozen_string_literal: true

require "json"

require_relative "snapshot_encoder/emitter"
require_relative "snapshot_encoder/pruner"
require_relative "snapshot_encoder/result"
require_relative "snapshot_encoder/tree_builder"

module Datadog
  module DI
    # The encoder of snapshot payloads for the snapshot intake. A payload
    # whose encoded size is at most the cap is encoded as JSON.dump
    # encodes it. A larger payload has its captured data pruned until it
    # fits, and a payload that still exceeds the cap after every prune
    # step is dropped.
    #
    # @api private
    module SnapshotEncoder
      # The JSON encodings of the member names that snapshot payloads
      # carry, shared by every payload.
      MEMBER_NAME_JSON = %w[
        type value isNull truncated size message stacktrace elements entries
        fields notCapturedReason notSerializedReason locals arguments throwable
        captureExpressions captures lines entry return fileName function
        lineNumber service debugger snapshot id timestamp evaluationErrors expr
        probe version location file method language stack duration host logger
        name method_name thread_name thread_id runtime_id dd.trace_id dd.span_id
        ddsource process_tags self @return
      ].map { |name| [name.freeze, JSON.dump(name).freeze] }.to_h.freeze

      # The marker that replaces a pruned value.
      PLACEHOLDER_JSON = JSON.dump({pruned: true}).freeze

      # The JSON encoding of the reason a cut value collection carries.
      PAYLOAD_TOO_LARGE_JSON = JSON.dump("payloadTooLarge").freeze

      # The byte size a primitive must exceed to be replaced by step 1.
      PRIMITIVE_SIZE_LIMIT = 200

      # The element count a collection must exceed to be cut by step 2,
      # and the number of elements a cut keeps.
      KEPT_ELEMENT_COUNT = 20

      # Encodes +snapshot+, pruning its captured data when its encoded size
      # exceeds +cap+.
      #
      # The encoder keeps no state between payloads: the builder and the
      # pruner it creates hold the state of one payload.
      #
      # @param snapshot [Hash] the snapshot payload
      # @param cap [Integer] the byte size the encoded payload must fit
      # @return [Result]
      # @raise [ArgumentError] when +snapshot+ is not a Hash
      # @raise [TypeError, JSON::GeneratorError, EncodingError] when a value cannot be encoded, as JSON.dump raises
      def self.encode(snapshot, cap)
        root, step1_candidates, step2_candidates, collections = TreeBuilder.new.build(snapshot)
        bytes = root.size
        if bytes <= cap
          return Result.new(
            encoded: Emitter.new.emit(root), pruned: false, bytes: bytes,
            replaced_primitives: 0, cut_collections: 0, replaced_collections: 0,
          )
        end

        counts = Pruner.new(
          root: root, step1_candidates: step1_candidates, step2_candidates: step2_candidates,
          collections: collections, cap: cap,
        ).prune
        fits = root.size <= cap
        Result.new(
          encoded: fits ? Emitter.new.emit(root) : nil, pruned: fits, bytes: bytes,
          replaced_primitives: counts.fetch(:replaced_primitives),
          cut_collections: counts.fetch(:cut_collections),
          replaced_collections: counts.fetch(:replaced_collections),
        )
      end
    end
  end
end
