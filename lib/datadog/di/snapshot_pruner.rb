# frozen_string_literal: true

require "json"

module Datadog
  module DI
    # Prunes oversized serialized snapshots to fit under a byte cap by
    # replacing the largest captured values with +{"pruned":true}+
    # markers, preserving the snapshot envelope.
    #
    # The transport serializes each snapshot Hash to JSON and drops any
    # whose encoded byte size exceeds the per-event cap
    # (MAX_SERIALIZED_SNAPSHOT_SIZE, 1 MB). This pruner instead walks the
    # snapshot's +captures+ subtree, measures each top-level captured
    # value (a +{type:...}+ object under +locals+ / +arguments+ /
    # +throwable+), and replaces the largest ones with the
    # +{"pruned":true}+ marker until the re-encoded snapshot fits under
    # the cap. A snapshot that cannot be reduced below the cap is dropped
    # by the caller.
    #
    # The pruner operates on the Ruby Hash (the form the transport holds
    # before encoding), measuring each captured value's byte size by
    # encoding it. Replacing whole captured variables (rather than
    # individual array elements) sends a portion of the captured data
    # with variable names preserved, satisfying the RFC C6 requirement
    # that oversized events are pruned rather than dropped whole.
    #
    # @api private
    module SnapshotPruner
      # Replacement for a pruned captured value. Matches Node.js and Java.
      PRUNED = {"pruned" => true}.freeze

      # Byte size of the pruned marker, precomputed once.
      PRUNED_BYTES = JSON.dump(PRUNED).bytesize

      # Prunes +snapshot+ to fit under +max_size+ bytes when encoded.
      #
      # @param snapshot [Hash] the snapshot payload Hash (as built by
      #   ProbeNotificationBuilder#build_snapshot_base).
      # @param max_size [Integer] maximum allowed encoded byte size.
      # @return [String, nil] the encoded (possibly pruned) JSON string
      #   if it fits under +max_size+, or nil if pruning could not
      #   reduce the snapshot below the cap.
      def self.prune(snapshot, max_size)
        encoded = JSON.dump(snapshot)
        return encoded if encoded.bytesize <= max_size

        # Work on a copy so the caller's snapshot is not mutated.
        copy = Marshal.load(Marshal.dump(snapshot))
        entries = collect_captured_entries(copy.dig(:debugger, :snapshot, :captures))
        return nil if entries.empty?

        overage = encoded.bytesize - max_size
        # Measure each captured value's encoded byte size. JSON.dump is
        # whitespace-free and deterministic, so a subtree's standalone
        # encoding is byte-identical to its span inside the full dump.
        measured = entries.map { |parent, key| [JSON.dump(parent[key]).bytesize, parent, key] }
        measured.sort_by! { |size, _, _| -size }

        reclaimed = 0
        measured.each do |size, parent, key|
          break if reclaimed >= overage
          parent[key] = PRUNED
          reclaimed += size - PRUNED_BYTES
        end

        final = JSON.dump(copy)
        final.bytesize <= max_size ? final : nil
      end

      # Collects the top-level captured value entries in +captures+:
      # each is a +[parent_hash, key]+ pair identifying a serialized
      # value object nested directly under +locals+, +arguments+, or
      # +throwable+. These are the prunable units; nested elements of a
      # captured collection are not collected separately (the whole
      # collection variable is pruned as one unit, preserving its name).
      #
      # @param captures [Hash] the +captures+ subtree of a snapshot.
      # @return [Array<[Hash, Symbol]>] list of +[parent, key]+ pairs.
      def self.collect_captured_entries(captures)
        entries = []
        return entries unless captures.is_a?(Hash)
        walk = ->(node) {
          case node
          when Hash
            if (locals = node[:locals]).is_a?(Hash)
              locals.each do |key, value|
                entries << [locals, key] if value.is_a?(Hash)
              end
            end
            if (arguments = node[:arguments]).is_a?(Hash)
              arguments.each do |key, value|
                entries << [arguments, key] if value.is_a?(Hash)
              end
            end
            if node[:throwable].is_a?(Hash)
              entries << [node, :throwable]
            end
            node.each_value { |value| walk.call(value) }
          when Array
            node.each { |value| walk.call(value) }
          end
        }
        walk.call(captures)
        entries
      end

      class << self
        private :collect_captured_entries
      end
    end
  end
end
