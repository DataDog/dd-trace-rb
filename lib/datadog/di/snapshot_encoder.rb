# frozen_string_literal: true

require "json"

module Datadog
  module DI
    # Encodes a snapshot Hash to a JSON string bounded by a per-event byte
    # cap, pruning captured values that do not fit.
    #
    # @api private
    module SnapshotEncoder
      # Byte cap applied to every scalar member of a retained captured
      # collection (+elements+, +entries+, +fields+).
      MAX_ITEM_BYTES = 2048

      # Byte allowance for a captured-value slot's framing: braces,
      # colons, commas, and the small fixed-size auxiliary fields such as
      # +truncated+, +size+, and +isNull+. Doubles as the fixed allowance
      # for a collection member name or a throwable stack frame, whose
      # encoded size has no constant-time bound.
      SLOT_OVERHEAD = 128

      # Maximum JSON expansion of one byte of a string value, via the
      # \uXXXX escaping of a control character.
      MAX_ESCAPE_EXPANSION = 6

      # Slot fields that hold a string of unbounded size: the type name,
      # the serialized value, the throwable message, and the capture
      # failure reasons.
      SLOT_STRING_FIELDS = %w[type value message notCapturedReason notSerializedReason].freeze

      # @type var marker: Hash[String, true]
      marker = {"pruned" => true}
      PRUNED = marker.freeze
      PRUNED_ENCODED = JSON.dump(PRUNED)

      # Encoded forms of the fixed snapshot keys.
      KEY_JSON = %w[
        type value isNull truncated size message stacktrace
        elements entries fields notCapturedReason notSerializedReason
        locals arguments throwable captureExpressions
        captures lines entry return
      ].each_with_object({}) { |key, json| json[key] = JSON.dump(key) }.freeze

      # Encodes +snapshot+ to JSON, pruning captured values that do not
      # fit +max_size+ bytes.
      #
      # @param snapshot [Hash] snapshot payload Hash
      # @param max_size [Integer] per-event byte cap
      # @return [Result] +encoded+ is the JSON string, of at most
      #   +max_size+ bytes, or nil when the snapshot cannot fit within
      #   +max_size+ even after pruning. +pruned+ is true when any
      #   captured-value slot was replaced with the pruned marker.
      # @raise [JSON::GeneratorError] when a captured value cannot be
      #   JSON-encoded
      def self.encode(snapshot, max_size)
        out = +""
        budget = Budget.new(max_size)
        pruned = false
        on_prune = -> { pruned = true }
        return Result.new(nil, false) unless encode_value(snapshot, out, budget, &on_prune)
        Result.new(out, pruned)
      end

      # Outcome of one encoding pass: +encoded+ [String, nil] is the JSON
      # string, or nil when the snapshot cannot fit within the cap even
      # after pruning; +pruned+ [Boolean] is true when any captured-value
      # slot was replaced with the pruned marker.
      Result = Struct.new(:encoded, :pruned)
      private_constant :Result

      # Byte budget for one encoding pass.
      #
      # @api private
      class Budget
        # Number of bytes still available for emission.
        #
        # @return [Integer] bytes still available
        attr_reader :remaining

        # Creates a budget of +remaining+ bytes.
        #
        # @param remaining [Integer] bytes available for emission
        def initialize(remaining)
          @remaining = remaining
        end

        # Consumes +bytes+ from the budget.
        #
        # @param bytes [Integer] number of bytes to consume
        # @return [void]
        def consume(bytes)
          @remaining = remaining - bytes
          nil
        end
      end
      private_constant :Budget

      class << self
        private

        # Encodes a JSON value: a Hash, an Array, or a scalar.
        #
        # @param node [Object] value to encode
        # @param out [String] output buffer
        # @param budget [Budget] byte budget charged for the emission
        # @param on_prune [Proc, nil] invoked when a captured-value slot
        #   is pruned
        # @return [Boolean] true when the value was emitted
        def encode_value(node, out, budget, &on_prune)
          if Hash === node
            encode_envelope_hash(node, out, budget, &on_prune)
          elsif Array === node
            encode_envelope_array(node, out, budget, &on_prune)
          else
            encode_scalar(node, out, budget)
          end
        end

        # Encodes one captured-value slot.
        #
        # @param slot [Object] captured-value slot
        # @param out [String] output buffer
        # @param budget [Budget] byte budget of the enclosing structure
        # @param item_cap [Integer, nil] byte cap for a scalar slot
        #   inside a captured collection; nil to gate against the whole
        #   remaining budget
        # @param on_prune [Proc, nil] invoked when the slot is pruned
        # @return [Boolean] true when the slot was emitted, either as its
        #   content or as the pruned marker
        def encode_slot(slot, out, budget, item_cap:, &on_prune)
          collection = Hash === slot && slot_collection?(slot)
          cap = if collection
            budget.remaining
          else
            item_cap ? [budget.remaining, item_cap].min : budget.remaining
          end
          oversized = if Hash === slot
            if collection
              slot_upper_bound(slot) > cap
            else
              slot_lower_bound(slot) > cap
            end
          else
            String === slot && slot.bytesize + 2 > cap
          end
          return emit_pruned(out, budget, &on_prune) if oversized
          # The slot's content is emitted into a scratch buffer first, so
          # a slot whose encoding exceeds the budget midway is discarded
          # whole; the enclosing output keeps whole slots only.
          scratch = String.new(encoding: Encoding::UTF_8)
          slot_budget = Budget.new(cap)
          emitted = if Hash === slot
            encode_slot_body(slot, scratch, slot_budget, &on_prune)
          else
            encode_value(slot, scratch, slot_budget, &on_prune)
          end
          return emit_pruned(out, budget, &on_prune) unless emitted
          emit_json_fragment(out, budget, scratch)
        end

        # Emits the fields of a Hash captured-value slot.
        #
        # @param slot [Hash] captured-value slot
        # @param out [String] output buffer
        # @param budget [Budget] byte budget for the slot's content
        # @param on_prune [Proc, nil] invoked when a nested slot is pruned
        # @return [Boolean] true when the slot was emitted in full
        def encode_slot_body(slot, out, budget, &on_prune)
          return false unless emit_json_fragment(out, budget, "{")
          first = true
          slot.each do |k, val|
            unless first
              return false unless emit_json_fragment(out, budget, ",")
            end
            first = false
            key = k.to_s
            return false unless emit_json_fragment(out, budget, KEY_JSON[key] || json_dump(key))
            return false unless emit_json_fragment(out, budget, ":")
            case key
            when "value"
              return false unless encode_scalar(val, out, budget)
            when "elements"
              return false unless encode_elements(val, out, budget, &on_prune)
            when "entries"
              return false unless encode_entries(val, out, budget, &on_prune)
            when "fields"
              return false unless encode_fields(val, out, budget, &on_prune)
            else
              # Remaining serializer fields (type, capture failure
              # reasons, message, stacktrace) and custom serializer
              # output are envelope data.
              return false unless encode_value(val, out, budget, &on_prune)
            end
          end
          emit_json_fragment(out, budget, "}")
        end

        # Encodes an +elements+ field: an Array whose members are
        # captured-value slots. A value of another type (custom serializer
        # output) is encoded as a generic JSON value.
        #
        # @param elements [Object] value of the +elements+ field
        # @param out [String] output buffer
        # @param budget [Budget] byte budget for the collection
        # @param on_prune [Proc, nil] invoked when a member is pruned
        # @return [Boolean] true when the collection was emitted in full
        def encode_elements(elements, out, budget, &on_prune)
          return encode_value(elements, out, budget, &on_prune) unless Array === elements
          return false unless emit_json_fragment(out, budget, "[")
          first = true
          elements.each do |slot|
            unless first
              return false unless emit_json_fragment(out, budget, ",")
            end
            first = false
            return false unless encode_slot(slot, out, budget, item_cap: MAX_ITEM_BYTES, &on_prune)
          end
          emit_json_fragment(out, budget, "]")
        end

        # Encodes an +entries+ field: an Array of [key, value] pairs of
        # captured-value slots. Pairs of another shape and values of
        # another type are encoded as generic JSON values.
        #
        # @param entries [Object] value of the +entries+ field
        # @param out [String] output buffer
        # @param budget [Budget] byte budget for the collection
        # @param on_prune [Proc, nil] invoked when a pair member is
        #   pruned
        # @return [Boolean] true when the collection was emitted in full
        def encode_entries(entries, out, budget, &on_prune)
          return encode_value(entries, out, budget, &on_prune) unless Array === entries
          return false unless emit_json_fragment(out, budget, "[")
          first = true
          entries.each do |pair|
            unless first
              return false unless emit_json_fragment(out, budget, ",")
            end
            first = false
            encoded = if Array === pair
              encode_slot_pair(pair, out, budget, &on_prune)
            else
              encode_value(pair, out, budget, &on_prune)
            end
            return false unless encoded
          end
          emit_json_fragment(out, budget, "]")
        end

        # Encodes one [key, value] pair of an +entries+ field.
        #
        # @param pair [Array] two-element Array of captured-value slots
        # @param out [String] output buffer
        # @param budget [Budget] byte budget for the pair
        # @param on_prune [Proc, nil] invoked when a pair member is pruned
        # @return [Boolean] true when the pair was emitted in full
        def encode_slot_pair(pair, out, budget, &on_prune)
          return false unless emit_json_fragment(out, budget, "[")
          return false unless encode_slot(pair[0], out, budget, item_cap: MAX_ITEM_BYTES, &on_prune)
          return false unless emit_json_fragment(out, budget, ",")
          return false unless encode_slot(pair[1], out, budget, item_cap: MAX_ITEM_BYTES, &on_prune)
          emit_json_fragment(out, budget, "]")
        end

        # Encodes a +fields+ field: a Hash mapping member names to
        # captured-value slots. A value of another type is encoded as a
        # generic JSON value.
        #
        # @param fields [Object] value of the +fields+ field
        # @param out [String] output buffer
        # @param budget [Budget] byte budget for the collection
        # @param on_prune [Proc, nil] invoked when a member is pruned
        # @return [Boolean] true when the collection was emitted in full
        def encode_fields(fields, out, budget, &on_prune)
          return encode_value(fields, out, budget, &on_prune) unless Hash === fields
          return false unless emit_json_fragment(out, budget, "{")
          first = true
          fields.each do |name, slot|
            unless first
              return false unless emit_json_fragment(out, budget, ",")
            end
            first = false
            return false unless emit_json_fragment(out, budget, json_dump(name.to_s))
            return false unless emit_json_fragment(out, budget, ":")
            return false unless encode_slot(slot, out, budget, item_cap: MAX_ITEM_BYTES, &on_prune)
          end
          emit_json_fragment(out, budget, "}")
        end

        # Encodes a +locals+, +arguments+, or +captureExpressions+ value: a
        # Hash mapping variable names to captured-value slots. A value of
        # another type is encoded as a generic JSON value.
        #
        # @param hash [Object] value of the +locals+, +arguments+, or
        #   +captureExpressions+ field
        # @param out [String] output buffer
        # @param budget [Budget] byte budget for the collection
        # @param on_prune [Proc, nil] invoked when a slot is pruned
        # @return [Boolean] true when the collection was emitted in full
        def encode_slot_hash(hash, out, budget, &on_prune)
          return encode_value(hash, out, budget, &on_prune) unless Hash === hash
          return false unless emit_json_fragment(out, budget, "{")
          first = true
          hash.each do |name, slot|
            unless first
              return false unless emit_json_fragment(out, budget, ",")
            end
            first = false
            return false unless emit_json_fragment(out, budget, json_dump(name.to_s))
            return false unless emit_json_fragment(out, budget, ":")
            return false unless encode_slot(slot, out, budget, item_cap: nil, &on_prune)
          end
          emit_json_fragment(out, budget, "}")
        end

        # Encodes a structural envelope Hash. The +locals+, +arguments+, and
        # +captureExpressions+ values are Hashes of {variable name: slot};
        # the +throwable+ value is a single slot. Other values are envelope
        # data and are emitted as-is.
        #
        # @param hash [Hash] envelope Hash to encode
        # @param out [String] output buffer
        # @param budget [Budget] byte budget for the structure
        # @param on_prune [Proc, nil] invoked when a captured-value slot
        #   is pruned
        # @return [Boolean] true when the structure was emitted in full
        def encode_envelope_hash(hash, out, budget, &on_prune)
          return false unless emit_json_fragment(out, budget, "{")
          first = true
          hash.each do |k, val|
            unless first
              return false unless emit_json_fragment(out, budget, ",")
            end
            first = false
            key = k.to_s
            return false unless emit_json_fragment(out, budget, KEY_JSON[key] || json_dump(key))
            return false unless emit_json_fragment(out, budget, ":")
            case key
            when "locals", "arguments", "captureExpressions"
              return false unless encode_slot_hash(val, out, budget, &on_prune)
            when "throwable"
              if val.nil?
                return false unless encode_scalar(val, out, budget)
              else
                return false unless encode_slot(val, out, budget, item_cap: nil, &on_prune)
              end
            else
              return false unless encode_value(val, out, budget, &on_prune)
            end
          end
          emit_json_fragment(out, budget, "}")
        end

        # Encodes a structural envelope Array.
        #
        # @param array [Array] envelope Array to encode
        # @param out [String] output buffer
        # @param budget [Budget] byte budget for the structure
        # @param on_prune [Proc, nil] invoked when a captured-value slot
        #   is pruned
        # @return [Boolean] true when the structure was emitted in full
        def encode_envelope_array(array, out, budget, &on_prune)
          return false unless emit_json_fragment(out, budget, "[")
          first = true
          array.each do |val|
            unless first
              return false unless emit_json_fragment(out, budget, ",")
            end
            first = false
            return false unless encode_value(val, out, budget, &on_prune)
          end
          emit_json_fragment(out, budget, "]")
        end

        # Dumps +value+ to JSON for emission, normalizing the encoding
        # failure class across the supported range.
        #
        # @param value [Object] value to dump
        # @return [String] JSON encoding of +value+
        # @raise [JSON::GeneratorError] when +value+ cannot be
        #   JSON-encoded
        def json_dump(value)
          JSON.dump(value)
        rescue Encoding::UndefinedConversionError => exc
          raise JSON::GeneratorError, exc.message
        end

        # Encodes a scalar value to JSON once and emits it when it fits
        # the budget.
        #
        # @param scalar [Object] scalar value to encode
        # @param out [String] output buffer
        # @param budget [Budget] byte budget charged for the emission
        # @return [Boolean] true when the value was emitted
        def encode_scalar(scalar, out, budget)
          emit_json_fragment(out, budget, json_dump(scalar))
        end

        # Appends an already-encoded JSON fragment when it fits the
        # budget.
        #
        # @param out [String] output buffer
        # @param budget [Budget] byte budget charged for the fragment
        # @param fragment [String] pre-encoded JSON fragment
        # @return [Boolean] true when the fragment was appended
        def emit_json_fragment(out, budget, fragment)
          return false if budget.remaining < fragment.bytesize
          out << fragment
          budget.consume(fragment.bytesize)
          true
        end

        # Emits the pruned marker in place of a captured value.
        #
        # @param out [String] output buffer
        # @param budget [Budget] byte budget charged for the marker
        # @param on_prune [Proc, nil] invoked when the marker is emitted
        # @return [Boolean] true when the marker was emitted
        def emit_pruned(out, budget, &on_prune)
          return false unless emit_json_fragment(out, budget, PRUNED_ENCODED)
          on_prune&.call
          true
        end

        # Returns whether the slot holds a captured collection: an
        # +elements+ or +entries+ Array, a +fields+ Hash, or a +stacktrace+
        # Array.
        #
        # @param slot [Hash] captured-value slot
        # @return [Boolean] whether the slot holds a collection
        def slot_collection?(slot)
          Array === field_value(slot, "elements") ||
            Array === field_value(slot, "entries") ||
            Hash === field_value(slot, "fields") ||
            Array === field_value(slot, "stacktrace")
        end

        # Constant-time upper bound on a collection slot's encoded size.
        #
        # @param slot [Hash] captured-value slot
        # @return [Integer] upper bound on the slot's encoded byte size
        def slot_upper_bound(slot)
          v = SLOT_OVERHEAD +
            slot_string_fields_bound(slot, bytes_per_byte: MAX_ESCAPE_EXPANSION, bytes_per_field: 0)
          if (elements = field_value(slot, "elements")) && Array === elements
            v += 2 + elements.length * (MAX_ITEM_BYTES + 1)
          end
          if (entries = field_value(slot, "entries")) && Array === entries
            v += 2 + entries.length * (2 * (MAX_ITEM_BYTES + 1) + 3)
          end
          if (fields = field_value(slot, "fields")) && Hash === fields
            v += 2 + fields.size * (MAX_ITEM_BYTES + 1 + SLOT_OVERHEAD)
          end
          if (stacktrace = field_value(slot, "stacktrace")) && Array === stacktrace
            v += 2 + stacktrace.length * SLOT_OVERHEAD
          end
          v
        end

        # Lower bound on a scalar slot's encoded size.
        #
        # @param slot [Hash] captured-value slot
        # @return [Integer] lower bound on the slot's encoded byte size
        def slot_lower_bound(slot)
          2 + slot_string_fields_bound(slot, bytes_per_byte: 1, bytes_per_field: 2)
        end

        # Accumulates the slot's string fields into a size bound.
        #
        # @param slot [Hash] captured-value slot
        # @param bytes_per_byte [Integer] bytes counted per string byte
        # @param bytes_per_field [Integer] bytes counted per present
        #   string field
        # @return [Integer] bound contribution of the string fields
        def slot_string_fields_bound(slot, bytes_per_byte:, bytes_per_field:)
          total = 0
          SLOT_STRING_FIELDS.each do |field|
            value = field_value(slot, field)
            total += value.bytesize * bytes_per_byte + bytes_per_field if String === value
          end
          total
        end

        # Returns the value of +field+ in +slot+, matching Symbol and
        # String keys.
        #
        # @param slot [Hash] captured-value slot
        # @param field [String] field name
        # @return [Object, nil] the field value
        def field_value(slot, field)
          slot[field.to_sym] || slot[field]
        end
      end
    end
  end
end
