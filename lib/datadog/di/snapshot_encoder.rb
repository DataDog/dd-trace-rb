# frozen_string_literal: true

require "json"

module Datadog
  module DI
    # Encodes a snapshot Hash to JSON in a single pass, pruning captured
    # values that do not fit a per-event byte cap instead of dropping
    # the whole snapshot. Implements RFC C6 (per-event payload size cap
    # + pruning).
    #
    # The encoder walks the snapshot Hash once and emits JSON inline. The
    # structural envelope (service, debugger.snapshot probe/stack,
    # evaluationErrors, and the captures container) is emitted as-is; if
    # the envelope alone exceeds the cap the snapshot cannot fit and
    # +encode+ returns nil. The direct children of every +locals+,
    # +arguments+, and +throwable+ node under +captures+ are prunable
    # captured-value slots: a slot whose constant-time upper bound V
    # exceeds the remaining byte budget is replaced in place with
    # +{"pruned":true}+ and is not walked or encoded (project encoding
    # constraints A to D in requirements.md).
    #
    # +Serializer#serialize_value+ stores Integer and Float values as
    # +value: value.to_s+ with no truncation, so a captured value's
    # encoded size is unbounded. The encoder's per-slot V is computed
    # from +value.bytesize+ (O(1) in Ruby; * 6 bounds JSON \uXXXX
    # escape expansion), so an oversized integer or float leaf is pruned
    # to the marker without being encoded (constraint A: zero encodes of
    # the oversized value). Every retained leaf is thereby at most
    # MAX_ITEM_BYTES, so a collection's V = 2 + count * (MAX_ITEM_BYTES + 1)
    # is at least the collection's actual encoded size (constraint D).
    # This is C6 pruning in the encode walk, not a C5 serializer change.
    #
    # @api private
    module SnapshotEncoder
      # Per-leaf byte cap applied to every retained captured value inside
      # a collection, so a collection's lower bound
      # V = 2 + count * (MAX_ITEM_BYTES + 1) is at least its actual
      # encoded size (constraint D). Chosen at least as large as the
      # largest encoded scalar the serializer can produce under its
      # structural capture limits (a 255-char string escapes to ~1530
      # bytes), so legitimate max-length string slots are kept.
      MAX_ITEM_BYTES = 2048

      # Fixed overhead allowance for a scalar slot's framing (the
      # +{"type":"...","value":...}+ keys, braces, colons, and small
      # auxiliary fields such as +truncated+ or +size+). An upper bound;
      # the actual framing is smaller.
      SLOT_OVERHEAD = 128

      # Maximum JSON expansion of a single byte via \uXXXX escaping.
      MAX_ESCAPE_EXPANSION = 6

      PRUNED = {"pruned" => true}.freeze
      PRUNED_ENCODED = JSON.dump(PRUNED)

      # Encodes +snapshot+ to JSON in a single pass, pruning captured
      # values that do not fit +max_size+ bytes. Returns a +Result+
      # whose +encoded+ is the JSON string (at most +max_size+,
      # possibly pruned) or +nil+ when the structural envelope alone
      # exceeds +max_size+, and whose +pruned+ is true iff any
      # captured-value slot was replaced with the pruned marker.
      def self.encode(snapshot, max_size)
        out = +""
        budget = Budget.new(max_size)
        pruned = false
        unless encode_value(snapshot, out, budget, prunable: false) { |_, _| pruned = true }
          return Result.new(nil, false)
        end
        Result.new(out, pruned)
      end

      Result = Struct.new(:encoded, :pruned) do
        # +encoded+ is the JSON string, or +nil+ when the envelope
        # alone exceeds the cap. +pruned+ is true iff any
        # captured-value slot was replaced with the pruned marker.
      end
      private_constant :Result

      Budget = Struct.new(:remaining) do
        def consume(n)
          self.remaining = remaining - n
        end
      end
      private_constant :Budget

      class << self
        private

        def encode_value(node, out, budget, prunable:, &on_prune)
          if prunable
            encode_slot(node, out, budget, item_cap: nil, &on_prune)
          elsif node.is_a?(Hash)
            encode_envelope_hash(node, out, budget, &on_prune)
          elsif node.is_a?(Array)
            encode_envelope_array(node, out, budget, &on_prune)
          else
            encode_scalar(node, out, budget)
          end
        end

        # Encodes a prunable captured-value slot. If the slot's upper
        # bound V exceeds the byte budget, emits the pruned marker in
        # its place without walking or encoding the slot (constraints B
        # and D). +item_cap+ bounds each retained sub-item when set
        # (collections); +nil+ lets a top-level slot use the whole
        # remaining budget.
        def encode_slot(slot, out, budget, item_cap:, &on_prune)
          cap = item_cap ? [budget.remaining, item_cap].min : budget.remaining
          if slot_upper_bound(slot) > cap
            on_prune&.call(nil, nil)
            return emit_pruned(out, budget)
          end
          encode_slot_body(slot, out, budget, &on_prune)
        end

        # Emits a captured-value slot's fields. Sub-collections
        # (elements/entries/fields) recurse with each sub-item capped
        # at MAX_ITEM_BYTES so the enclosing collection's V holds.
        def encode_slot_body(slot, out, budget, &on_prune)
          out << "{"
          first = true
          slot.each do |k, val|
            out << "," unless first
            first = false
            out << JSON.dump(k.to_s)
            out << ":"
            case k.to_s
            when "value"
              encode_scalar(val, out, budget)
            when "elements"
              encode_slot_array(val, out, budget, &on_prune)
            when "entries"
              encode_slot_entries(val, out, budget, &on_prune)
            when "fields"
              encode_slot_hash(val, out, budget, &on_prune)
            else
              # type, notCapturedReason, notSerializedReason,
              # isNull, truncated, size, etc.
              encode_scalar(val, out, budget)
            end
          end
          out << "}"
          true
        end

        # Encodes a Hash of {name: slot} (a +locals+ or +arguments+
        # value, or an object +fields+ value): each child value is a
        # prunable captured-value slot.
        def encode_slot_hash(hash, out, budget, &on_prune)
          out << "{"
          first = true
          hash.each do |name, slot|
            out << "," unless first
            first = false
            out << JSON.dump(name.to_s)
            out << ":"
            return false unless encode_slot(slot, out, budget, item_cap: MAX_ITEM_BYTES, &on_prune)
          end
          out << "}"
          true
        end

        def encode_slot_array(array, out, budget, &on_prune)
          out << "["
          first = true
          array.each do |slot|
            out << "," unless first
            first = false
            return false unless encode_slot(slot, out, budget, item_cap: MAX_ITEM_BYTES, &on_prune)
          end
          out << "]"
          true
        end

        def encode_slot_entries(entries, out, budget, &on_prune)
          out << "["
          first = true
          entries.each do |pair|
            out << "," unless first
            first = false
            out << "["
            return false unless encode_slot(pair[0], out, budget, item_cap: MAX_ITEM_BYTES, &on_prune)
            out << ","
            return false unless encode_slot(pair[1], out, budget, item_cap: MAX_ITEM_BYTES, &on_prune)
            out << "]"
          end
          out << "]"
          true
        end

        # Encodes an envelope/container Hash. The +locals+ and
        # +arguments+ values are Hashes of {name: slot}; the
        # +throwable+ value is a single slot (or nil). Other keys
        # recurse as envelope.
        def encode_envelope_hash(hash, out, budget, &on_prune)
          out << "{"
          first = true
          hash.each do |k, val|
            out << "," unless first
            first = false
            out << JSON.dump(k.to_s)
            out << ":"
            case k.to_s
            when "locals", "arguments"
              return false unless encode_slot_hash(val, out, budget, &on_prune)
            when "throwable"
              if val.nil?
                return false unless encode_scalar(val, out, budget)
              else
                return false unless encode_slot(val, out, budget, item_cap: nil, &on_prune)
              end
            else
              return false unless encode_value(val, out, budget, prunable: false, &on_prune)
            end
          end
          out << "}"
          true
        end

        def encode_envelope_array(array, out, budget, &on_prune)
          out << "["
          first = true
          array.each do |elt|
            out << "," unless first
            first = false
            return false unless encode_value(elt, out, budget, prunable: false, &on_prune)
          end
          out << "]"
          true
        end

        def encode_scalar(scalar, out, budget)
          s = JSON.dump(scalar)
          return false if budget.remaining < s.bytesize
          out << s
          budget.consume(s.bytesize)
          true
        end

        def emit_pruned(out, budget)
          return false if budget.remaining < PRUNED_ENCODED.bytesize
          out << PRUNED_ENCODED
          budget.consume(PRUNED_ENCODED.bytesize)
          true
        end

        # Constant-time upper bound on a captured-value slot's encoded
        # size (constraint D). For a scalar slot, V is derived from
        # the already-stringified +value.bytesize+ (O(1)); for a
        # collection slot, V = 2 + count * (MAX_ITEM_BYTES + 1) where
        # count is the number of sub-slots (O(1) via length/size).
        def slot_upper_bound(slot)
          if (elements = field_value(slot, "elements"))
            2 + elements.length * (MAX_ITEM_BYTES + 1)
          elsif (entries = field_value(slot, "entries"))
            2 + entries.length * 2 * (MAX_ITEM_BYTES + 1)
          elsif (fields = field_value(slot, "fields")) && fields.is_a?(Hash)
            2 + fields.size * (MAX_ITEM_BYTES + 1)
          else
            value = field_value(slot, "value")
            vb = value.is_a?(String) ? value.bytesize * MAX_ESCAPE_EXPANSION : 0
            SLOT_OVERHEAD + vb
          end
        end

        def field_value(slot, key)
          slot[key.to_sym] || slot[key]
        end
      end
    end
  end
end
