# frozen_string_literal: true

require_relative "array_node"
require_relative "fragment_node"
require_relative "object_node"

module Datadog
  module DI
    module SnapshotEncoder
      # The pruner of one encoded tree. It changes only the encoded tree,
      # and each step ends as soon as the root size is at most the cap.
      #
      # Prunes in three steps: replaces captured values over 200 bytes,
      # largest first; shortens collections over 20 elements to their first
      # 20, largest first; replaces collections, deepest first, ending with
      # variable maps, throwables and capture sets. Java, Python, .NET,
      # Node.js and Go order pruning candidates by depth, notCapturedReason
      # and size and do not shorten collections; PHP stops capturing at its
      # size limit instead of pruning.
      #
      # @api private
      class Pruner
        # The +notCapturedReason+ value a cut keeps.
        TIMEOUT_REASON = "timeout"

        # The element members whose cut collection gets a +size+ member.
        SIZED_ELEMENT_MEMBERS = ["elements", "entries"].freeze

        # Initializes the pruner of one encoded tree.
        #
        # @param root [ObjectNode] the root of the encoded tree
        # @param step1_candidates [Array<Prunable>] the primitives over +PRIMITIVE_SIZE_LIMIT+ bytes
        # @param step2_candidates [Array<Prunable>] the collections with more than +KEPT_ELEMENT_COUNT+ elements
        # @param collections [Array<Prunable>] all collections
        # @param cap [Integer] the byte size the root must fit
        def initialize(root:, step1_candidates:, step2_candidates:, collections:, cap:)
          @root = root
          @step1_candidates = step1_candidates
          @step2_candidates = step2_candidates
          @collections = collections
          @cap = cap
          @removed_ranges = []
        end

        # The root of the encoded tree.
        # @return [ObjectNode]
        attr_reader :root

        # The byte size the root must fit.
        # @return [Integer]
        attr_reader :cap

        # Runs the three prune steps in order until the root size is at
        # most the cap.
        #
        # @return [Hash{Symbol => Integer}] the number of changes made by each step, under
        #   +:replaced_primitives+, +:cut_collections+ and +:replaced_collections+
        def prune
          replaced_primitives = replace_primitives
          cut_collections = fits? ? 0 : cut_collections_step
          replaced_collections = fits? ? 0 : replace_collections
          {
            replaced_primitives: replaced_primitives,
            cut_collections: cut_collections,
            replaced_collections: replaced_collections,
          }
        end

        private

        # The primitives over +PRIMITIVE_SIZE_LIMIT+ bytes.
        # @return [Array<Prunable>]
        attr_reader :step1_candidates

        # The collections with more than +KEPT_ELEMENT_COUNT+ elements.
        # @return [Array<Prunable>]
        attr_reader :step2_candidates

        # All collections.
        # @return [Array<Prunable>]
        attr_reader :collections

        # The ordinal ranges removed by step 2 cuts, as [first, last]
        # pairs sorted by first ordinal. The ranges do not overlap.
        # @return [Array<Array(Integer, Integer)>]
        attr_reader :removed_ranges

        # Whether the root size is at most the cap.
        #
        # @return [Boolean]
        def fits?
          root.size <= cap
        end

        # Step 1: replaces primitives over +PRIMITIVE_SIZE_LIMIT+ bytes with
        # the placeholder, largest first, then greater ordinal first. A
        # primitive's size does not change and a primitive holds no other
        # candidate, so the order sorted once stays correct.
        #
        # @return [Integer] the number of replaced primitives
        def replace_primitives
          count = 0
          step1_candidates.sort! { |a, b| (b.node.size <=> a.node.size).nonzero? || (b.ordinal <=> a.ordinal) }
          step1_candidates.each do |candidate|
            break if fits?

            replace_with_placeholder(candidate)
            count += 1
          end
          count
        end

        # Step 2: cuts collections over +KEPT_ELEMENT_COUNT+ elements to
        # their first +KEPT_ELEMENT_COUNT+, largest first, then greater
        # ordinal first. A collection is larger than every collection
        # inside it, so the candidates enclosing a collection are cut
        # before it, and a cut changes the size of no candidate still
        # waiting: the order sorted once stays correct.
        #
        # @return [Integer] the number of cut collections
        def cut_collections_step
          count = 0
          step2_candidates.sort! { |a, b| (b.node.size <=> a.node.size).nonzero? || (b.ordinal <=> a.ordinal) }
          step2_candidates.each do |candidate|
            break if fits?
            next if removed?(candidate.ordinal)

            cut(candidate)
            count += 1
          end
          count
        end

        # Step 3: replaces collections outside removed ranges with the
        # placeholder, deepest first, then greater ordinal first. Every
        # collection deeper than the current one is replaced before it,
        # so a replaced collection holds no candidate.
        #
        # @return [Integer] the number of replaced collections
        def replace_collections
          count = 0
          collections.sort! { |a, b| (b.depth <=> a.depth).nonzero? || (b.ordinal <=> a.ordinal) }
          collections.each do |candidate|
            break if fits?
            next if removed?(candidate.ordinal)

            replace_with_placeholder(candidate)
            count += 1
          end
          count
        end

        # Replaces a candidate's node with the placeholder.
        #
        # @param candidate [Prunable] the replaced primitive or collection
        # @return [void]
        def replace_with_placeholder(candidate)
          candidate.parent.replace_child(candidate.index, FragmentNode.new(PLACEHOLDER_JSON))
        end

        # Cuts a collection to its first +KEPT_ELEMENT_COUNT+ elements,
        # records the removed ordinal range and marks a value collection.
        #
        # @param candidate [Prunable] the cut collection
        # @return [void]
        def cut(candidate)
          container = candidate.element_container
          if ObjectNode === container
            container.truncate_members(KEPT_ELEMENT_COUNT)
          else
            elements = container #: ArrayNode
            elements.truncate_elements(KEPT_ELEMENT_COUNT)
          end
          cut_start_ordinal = candidate.cut_start_ordinal #: Integer
          record_removed_range(cut_start_ordinal, candidate.last_ordinal)

          if candidate.element_member.nil?
            # A variable map gets no marker member: the Live Debugger UI reads every
            # member of it as a variable. The cut is reported only by the
            # capture.incomplete{reason:payloadTooLarge} metric.
            return
          end

          mark_cut(candidate)
        end

        # Marks a cut value collection with +notCapturedReason+
        # +payloadTooLarge+, keeping an existing +timeout+ reason, and adds
        # the pre-cut +size+ to an +elements+ or +entries+ collection that
        # has neither member.
        #
        # @param candidate [Prunable] the cut value collection
        # @return [void]
        def mark_cut(candidate)
          node = candidate.node #: ObjectNode
          reason_index = candidate.reason_member_index
          if reason_index.nil?
            node.append_member("notCapturedReason", MEMBER_NAME_JSON.fetch("notCapturedReason"),
              FragmentNode.new(PAYLOAD_TOO_LARGE_JSON))
            if candidate.size_member_index.nil? && SIZED_ELEMENT_MEMBERS.include?(candidate.element_member)
              node.append_member("size", MEMBER_NAME_JSON.fetch("size"),
                FragmentNode.new(candidate.element_count.to_s))
            end
          elsif candidate.not_captured_reason != TIMEOUT_REASON
            node.replace_child(reason_index, FragmentNode.new(PAYLOAD_TOO_LARGE_JSON))
          end
          nil
        end

        # Records a removed ordinal range, keeping the ranges sorted by
        # first ordinal.
        #
        # @param first_ordinal [Integer] the first removed ordinal
        # @param last_ordinal [Integer] the last removed ordinal
        # @return [void]
        def record_removed_range(first_ordinal, last_ordinal)
          position = removed_ranges.bsearch_index { |range| range[0] > first_ordinal } || removed_ranges.length
          removed_ranges.insert(position, [first_ordinal, last_ordinal])
          nil
        end

        # Whether an ordinal lies in a removed range.
        #
        # @param ordinal [Integer] the ordinal tested
        # @return [Boolean]
        def removed?(ordinal)
          position = removed_ranges.bsearch_index { |range| range[0] > ordinal } || removed_ranges.length
          return false if position == 0

          removed_ranges[position - 1][1] >= ordinal
        end
      end
    end
  end
end
