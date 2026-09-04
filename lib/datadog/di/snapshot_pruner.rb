# frozen_string_literal: true

require "json"

module Datadog
  module DI
    # Prunes oversized serialized snapshots to fit under a byte cap by
    # replacing the largest captured values with +{"pruned":true}+
    # markers, preserving the snapshot envelope.
    #
    # The transport serializes each snapshot Hash to JSON once and passes
    # the resulting String here as +encoded+. This pruner never encodes
    # the original snapshot again: it walks the snapshot's +captures+
    # subtree, measures each top-level captured value (a +{type:...}+
    # object under +locals+, +arguments+, +captureExpressions+, or
    # +throwable+) by encoding it once, and replaces the largest ones
    # with the +{"pruned":true}+ marker on a deep copy, which is
    # encoded once. If pruning individual values cannot bring the
    # snapshot under the cap, the entire +captures+ subtree is
    # collapsed to the marker so the snapshot envelope (probe id,
    # stack, message) is still delivered. A snapshot whose envelope
    # alone exceeds the cap cannot be reduced and is dropped by the
    # caller.
    #
    # No object is passed to JSON.dump more than once: the snapshot is
    # dumped once by the caller (this method reuses that encoding
    # instead of re-dumping the snapshot), each captured value is
    # dumped once for measurement, and the pruned copy is dumped
    # once for output.
    #
    # Replacing whole captured variables (rather than individual array
    # elements) preserves variable names so a portion of the captured
    # data is delivered instead of dropping the whole event.
    #
    # @api private
    module SnapshotPruner
      # Replacement for a pruned captured value. Matches Node.js and Java.
      PRUNED = {"pruned" => true}.freeze

      # Byte size of the pruned marker, precomputed once.
      PRUNED_BYTES = JSON.dump(PRUNED).bytesize

      # Prunes +snapshot+ to fit under +max_size+ bytes when encoded.
      #
      # The caller must encode +snapshot+ exactly once and pass the
      # result as +encoded+; this method relies on +encoded.bytesize+
      # for the size check and the overage calculation and does not
      # encode +snapshot+ again. When the snapshot already fits,
      # +encoded+ is returned unchanged.
      #
      # @param snapshot [Hash] the snapshot payload Hash (as built by
      #   ProbeNotificationBuilder#build_snapshot_base).
      # @param max_size [Integer] maximum allowed encoded byte size.
      # @param encoded [String] the result of encoding +snapshot+ once.
      # @return [String, nil] the encoded (possibly pruned) JSON string
      #   if it fits under +max_size+, or nil if the snapshot envelope
      #   alone exceeds the cap and cannot be reduced.
      def self.prune(snapshot, max_size, encoded:)
        return encoded if encoded.bytesize <= max_size

        copy = Marshal.load(Marshal.dump(snapshot))
        entries = collect_captured_entries(copy.dig(:debugger, :snapshot, :captures))

        final = nil
        unless entries.empty?
          overage = encoded.bytesize - max_size
          # Measure each captured value's encoded byte size. JSON.dump is
          # whitespace-free and deterministic, so a subtree's standalone
          # encoding is byte-identical to its span inside the full dump.
          sizes = entries.map { |parent, key| JSON.dump(parent[key]).bytesize }

          # Prune the largest captured values first until the overage is
          # reclaimed.
          reclaimed = 0
          (0...entries.size).sort_by { |i| -sizes[i] }.each do |i|
            break if reclaimed >= overage
            parent, key = entries[i]
            parent[key] = PRUNED
            reclaimed += sizes[i] - PRUNED_BYTES
          end

          final = JSON.dump(copy)
        end

        # If individual pruning did not fit (final is nil or still too
        # big), collapse the entire captures subtree to the pruned
        # marker so the snapshot envelope (probe id, stack, message) is
        # still delivered. Drop only when the envelope alone exceeds
        # the cap.
        if final.nil? || final.bytesize > max_size
          snapshot_node = copy.dig(:debugger, :snapshot)
          snapshot_node[:captures] = PRUNED if snapshot_node.is_a?(Hash)
          final = JSON.dump(copy)
        end

        return nil if final.bytesize > max_size
        final
      end

      # Returns the prunable captured-value entries in +captures+.
      #
      # @param captures [Hash] the +captures+ subtree of a snapshot.
      # @return [Array<[Hash, Symbol]> the prunable entries.
      def self.collect_captured_entries(captures)
        entries = []
        return entries unless captures.is_a?(Hash)
        collect_captured_entries_into(captures, entries)
        entries
      end

      # Recursively appends each top-level captured value entry found in
      # +node+ to +entries+: each entry is a +[parent_hash, key]+ pair
      # identifying a serialized value object nested directly under
      # +locals+, +arguments+, +captureExpressions+, or +throwable+.
      # Nested elements of a captured collection are not appended
      # separately (the whole collection variable is pruned as one
      # unit, preserving its name).
      #
      # @param node [untyped] a subtree of the +captures+ Hash.
      # @param entries [Array<[Hash, Symbol]>] the accumulator.
      def self.collect_captured_entries_into(node, entries)
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
          if (capture_expressions = node[:captureExpressions]).is_a?(Hash)
            capture_expressions.each do |key, value|
              entries << [capture_expressions, key] if value.is_a?(Hash)
            end
          end
          if node[:throwable].is_a?(Hash)
            entries << [node, :throwable]
          end
          node.each_value { |value| collect_captured_entries_into(value, entries) }
        when Array
          node.each { |value| collect_captured_entries_into(value, entries) }
        end
      end

      class << self
        private :collect_captured_entries
        private :collect_captured_entries_into
      end
    end
  end
end
