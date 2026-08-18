# frozen_string_literal: true

require "set"

module Datadog
  module OpenFeature
    module FlagEvaluation
      # Two-tier aggregation for EVP flagevaluation events.
      #
      # Two-tier design:
      # - full-tier  key: (flag_key, variant, allocation_key, runtime_default, error_message, targeting_key, canonical_context_key)
      # - degraded-tier key: (flag_key, variant, allocation_key, runtime_default, error_message)
      # - Drop-and-count when degraded tier is full
      # - canonical_context_key: sorted type-tagged length-delimited encoding (no hash digest)
      # - Caps: global_cap=131_072 / per_flag_cap=10_000 / degraded_cap=32_768
      #
      # Context bounding: the writer applies `bounded_context_snapshot` on the evaluation
      # thread before enqueue, so the queue only ever holds an already-bounded, flattened
      # snapshot. `record` receives that snapshot and keys on it directly.
      class Aggregator
        # Cross-SDK context caps (RFC: "Kept aligned with the cross-SDK RFC").
        MAX_CONTEXT_FIELDS = 256
        MAX_FIELD_LENGTH = 256
        MAX_KEY_LENGTH = 256
        MAX_LIST_ELEMENTS = 256
        MAX_STRUCTURE_PROPERTIES = 256
        MAX_SNAPSHOT_DEPTH = 4

        # Truncation reason labels, surfaced on the `flagevaluation.context.truncated`
        # telemetry counter so operators can tell which cap was hit.
        REASON_MAX_CONTEXT_FIELDS = "max_context_fields"
        REASON_MAX_FIELD_LENGTH = "max_field_length"
        REASON_MAX_KEY_LENGTH = "max_key_length"
        REASON_MAX_LIST_ELEMENTS = "max_list_elements"
        REASON_MAX_STRUCTURE_PROPERTIES = "max_structure_properties"
        REASON_MAX_SNAPSHOT_DEPTH = "max_snapshot_depth"

        # Type tags so values of different Ruby types never collide in the canonical key.
        CTX_TAG_STRING = "s"
        CTX_TAG_BOOL = "b"
        CTX_TAG_INTEGER = "i"
        CTX_TAG_FLOAT = "f"
        CTX_TAG_OTHER = "o"

        EVAL_SCALE_TARGET_FLAGS = 2_500
        EVAL_SCALE_FULL_BUCKETS_PER_FLAG = 50
        EVAL_SCALE_USERS_PER_FLAG = 1_000
        EVAL_SCALE_PER_FLAG_HEADROOM_MULTIPLIER = 10
        EVAL_SCALE_DEGRADED_BUCKETS_PER_FLAG = 10
        EVAL_SCALE_FULL_BUCKET_TARGET = EVAL_SCALE_TARGET_FLAGS * EVAL_SCALE_FULL_BUCKETS_PER_FLAG
        EVAL_SCALE_PER_FLAG_BUCKET_TARGET = EVAL_SCALE_PER_FLAG_HEADROOM_MULTIPLIER * EVAL_SCALE_USERS_PER_FLAG
        EVAL_SCALE_DEGRADED_BUCKET_TARGET = EVAL_SCALE_TARGET_FLAGS * EVAL_SCALE_DEGRADED_BUCKETS_PER_FLAG

        DEFAULT_GLOBAL_CAP = 131_072
        DEFAULT_PER_FLAG_CAP = EVAL_SCALE_PER_FLAG_BUCKET_TARGET
        DEFAULT_DEGRADED_CAP = 32_768

        attr_reader :dropped_degraded_overflow

        def initialize(
          global_cap: DEFAULT_GLOBAL_CAP,
          per_flag_cap: DEFAULT_PER_FLAG_CAP,
          degraded_cap: DEFAULT_DEGRADED_CAP
        )
          @global_cap = global_cap
          @per_flag_cap = per_flag_cap
          @degraded_cap = degraded_cap

          @mutex = Mutex.new
          # full-tier: Array key -> Hash entry
          @full = {}
          # degraded-tier: Array key -> Hash entry
          @degraded = {}
          # per-flag full-bucket count for per_flag_cap enforcement
          @per_flag_full = Hash.new(0)
          @global_count = 0
          @dropped_degraded_overflow = 0
        end

        # Record one evaluation event. Thread-safe. Called from the background writer.
        def record(
          flag_key:, variant:, allocation_key:, targeting_key:, eval_time_ms:, attrs:, error_message: nil,
          runtime_default: nil, observe_full_evaluation_data: false, error_code: nil
        )
          runtime_default = variant.nil? if runtime_default.nil?
          runtime_default = !!runtime_default
          observe_full_evaluation_data = observe_full_evaluation_data == true

          # Normalize nil/empty strings
          variant = variant.to_s
          allocation_key = allocation_key.to_s
          error_message = error_message.to_s
          targeting_key = targeting_key.to_s

          if observe_full_evaluation_data
            # `attrs` is already the bounded, flattened snapshot produced by the writer on
            # the evaluation thread. Key on it directly.
            context_key = canonical_context_key(attrs)
            error_dimension = error_message
            full_key = [
              flag_key, variant, allocation_key, runtime_default, error_dimension,
              targeting_key, context_key, true,
            ]
          else
            # Consent off: the error message is redacted to the error code on emit, so the
            # error code is the bucket dimension (keying on the raw message would split
            # buckets that serialize to identical rows and burn the per-flag cap).
            error_dimension = error_code.to_s
            full_key = [
              flag_key, variant, allocation_key, runtime_default, error_dimension,
              targeting_key, false,
            ]
          end
          evaluation_time_ms = eval_time_ms.to_i

          @mutex.synchronize do
            # --- Full tier ---
            if (entry = @full[full_key])
              observe(entry, evaluation_time_ms)
              return
            end

            per_flag_count = @per_flag_full[flag_key]
            if per_flag_count >= @per_flag_cap
              add_to_degraded(
                flag_key, variant, allocation_key, runtime_default, error_message, evaluation_time_ms,
                observe_full_evaluation_data: observe_full_evaluation_data, error_code: error_code
              )
              return
            end

            # Count the full-tier attempt before checking the global cap so per-flag overflow stays
            # active even when the global full-tier cap is already saturated.
            @per_flag_full[flag_key] = per_flag_count + 1

            if @global_count < @global_cap
              entry = new_entry(
                evaluation_time_ms,
                runtime_default: runtime_default,
                error_message: error_message,
                targeting_key: targeting_key,
                context_attrs: observe_full_evaluation_data ? attrs : nil,
                observe_full_evaluation_data: observe_full_evaluation_data,
                error_code: error_code
              )
              @full[full_key] = entry
              @global_count += 1
            else
              # Route to degraded tier
              add_to_degraded(
                flag_key, variant, allocation_key, runtime_default, error_message, evaluation_time_ms,
                observe_full_evaluation_data: observe_full_evaluation_data, error_code: error_code
              )
            end
          end
        end

        # Flush aggregation maps, reset state, return snapshot.
        # The overflow count is included in the snapshot so the caller can emit it before
        # it is reset (never reset-without-emit).
        def flush_and_reset
          @mutex.synchronize do
            full_snapshot = @full
            degraded_snapshot = @degraded
            dropped_snapshot = @dropped_degraded_overflow

            @full = {}
            @degraded = {}
            @per_flag_full = Hash.new(0)
            @global_count = 0
            @dropped_degraded_overflow = 0

            {full: full_snapshot, degraded: degraded_snapshot, dropped_degraded_overflow: dropped_snapshot}
          end
        end

        # Bound and flatten the caller's evaluation context on the evaluation thread,
        # before enqueue, so the async queue only ever holds an already-bounded snapshot.
        # Returns the flattened (dot-notation) context and the set of truncation reasons
        # hit, which the writer surfaces on the `flagevaluation.context.truncated` counter.
        #
        # Cost is O(kept) (bounded by the caps), never O(supplied): Ruby Hash iteration is
        # deterministic insertion order, so the caps are enforced by stopping at the limit
        # rather than by sorting the full input. This is the cross-SDK recommendation for
        # languages with deterministic iteration (Ruby truncates; Go omits because its map
        # iteration is randomized per call).
        def self.bounded_context_snapshot(attrs)
          return [{}, []] unless attrs.is_a?(Hash) && !attrs.empty?

          flattened = {}
          reasons = Set.new
          seen = {attrs.object_id => true}
          attrs.each do |key, value|
            break if flattened.size >= MAX_CONTEXT_FIELDS
            bounded_flatten(key.to_s, value, flattened, seen, 0, reasons)
          end
          reasons << REASON_MAX_CONTEXT_FIELDS if flattened.size >= MAX_CONTEXT_FIELDS
          [flattened, reasons.to_a]
        end

        def self.bounded_flatten(prefix, value, output, seen, depth, reasons)
          return if value.nil?
          return if output.size >= MAX_CONTEXT_FIELDS
          return if depth > MAX_SNAPSHOT_DEPTH
          return if prefix.length > MAX_KEY_LENGTH

          case value
          when Hash
            return if value.empty?

            object_id = value.object_id
            return if seen[object_id]

            seen[object_id] = true
            walked = 0
            value.each do |key, child_value|
              break if output.size >= MAX_CONTEXT_FIELDS
              break if walked >= MAX_STRUCTURE_PROPERTIES
              bounded_flatten("#{prefix}.#{key}", child_value, output, seen, depth + 1, reasons)
              walked += 1
            end
            reasons << REASON_MAX_STRUCTURE_PROPERTIES if value.size > MAX_STRUCTURE_PROPERTIES
            reasons << REASON_MAX_CONTEXT_FIELDS if output.size >= MAX_CONTEXT_FIELDS
            seen.delete(object_id)
          when Array
            return if value.empty?

            object_id = value.object_id
            return if seen[object_id]

            seen[object_id] = true
            reasons << REASON_MAX_LIST_ELEMENTS if value.size > MAX_LIST_ELEMENTS
            walked = 0
            value.each_with_index do |child_value, index|
              break if output.size >= MAX_CONTEXT_FIELDS
              break if walked >= MAX_LIST_ELEMENTS
              bounded_flatten("#{prefix}.#{index}", child_value, output, seen, depth + 1, reasons)
              walked += 1
            end
            reasons << REASON_MAX_CONTEXT_FIELDS if output.size >= MAX_CONTEXT_FIELDS
            seen.delete(object_id)
          else
            if value.is_a?(String) && value.length > MAX_FIELD_LENGTH
              reasons << REASON_MAX_FIELD_LENGTH
              return
            end
            output[prefix] = begin
              value.dup
            rescue TypeError
              value
            end
          end
        end
        private_class_method :bounded_flatten

        # Canonical context key: sorted type-tagged length-delimited encoding.
        # Each field is: 8-byte big-endian key length + key bytes + type-tag byte +
        #                8-byte big-endian value length + value bytes.
        # No hash digest — the key IS the full encoding (collision-free, no FNV).
        def canonical_context_key(attrs)
          return "" if attrs.nil? || attrs.empty?

          buffer = String.new("", encoding: Encoding::BINARY)
          attrs.keys.sort.each do |key|
            value = attrs[key]
            buffer << length_delimited(key.to_s)
            buffer << context_value_bytes(value)
          end
          buffer
        end

        private

        def context_value_bytes(value)
          tag, encoded = case value
          when String then [CTX_TAG_STRING, value.to_s]
          when TrueClass, FalseClass then [CTX_TAG_BOOL, value.to_s]
          when Integer then [CTX_TAG_INTEGER, value.to_s]
          when Float then [CTX_TAG_FLOAT, value.to_s]
          else [CTX_TAG_OTHER, value.to_s]
          end
          String.new(tag, encoding: Encoding::BINARY) + length_delimited(encoded)
        end

        # 8-byte big-endian length prefix + raw bytes. Unambiguous field boundary.
        def length_delimited(string)
          bytes = string.encode(Encoding::BINARY, invalid: :replace, undef: :replace)
          byte_length = bytes.bytesize
          # Build 8-byte big-endian length
          length_bytes = String.new("", encoding: Encoding::BINARY)
          8.times do |index|
            length_bytes.prepend(((byte_length >> (8 * index)) & 0xFF).chr(Encoding::BINARY))
          end
          length_bytes + bytes
        end

        def new_entry(
          evaluation_time_ms, runtime_default:, error_message: nil, targeting_key: nil, context_attrs: nil,
          observe_full_evaluation_data: false, error_code: nil
        )
          {
            count: 1,
            first_evaluation: evaluation_time_ms,
            last_evaluation: evaluation_time_ms,
            runtime_default: runtime_default,
            error_message: error_message,
            error_code: error_code,
            targeting_key: targeting_key,
            context_attrs: context_attrs,
            observe_full_evaluation_data: observe_full_evaluation_data,
          }
        end

        def observe(entry, evaluation_time_ms)
          entry[:count] += 1
          entry[:first_evaluation] = evaluation_time_ms if evaluation_time_ms < entry[:first_evaluation]
          entry[:last_evaluation] = evaluation_time_ms if evaluation_time_ms > entry[:last_evaluation]
        end

        def add_to_degraded(
          flag_key, variant, allocation_key, runtime_default, error_message, evaluation_time_ms,
          observe_full_evaluation_data: false, error_code: nil
        )
          # Consent and the emitted error dimension are part of the degraded key so that
          # consent-on and consent-off evaluations, and errors that redact to different
          # codes, do not merge.
          error_dimension = observe_full_evaluation_data ? error_message : error_code.to_s
          degraded_key = [
            flag_key, variant, allocation_key, runtime_default, error_dimension, observe_full_evaluation_data,
          ]

          if (entry = @degraded[degraded_key])
            observe(entry, evaluation_time_ms)
            return
          end

          # New degraded bucket — check degraded_cap (terminal tier)
          if @degraded.size >= @degraded_cap
            # Terminal tier full — drop and count (explicit overflow counter)
            @dropped_degraded_overflow += 1
            return
          end

          # Degraded entry omits targeting_key + context_attrs (schema omitempty fields),
          # but carries consent and the error code so the writer can redact the error
          # message correctly on emit.
          @degraded[degraded_key] = new_entry(
            evaluation_time_ms,
            runtime_default: runtime_default,
            error_message: error_message,
            observe_full_evaluation_data: observe_full_evaluation_data,
            error_code: error_code
          )
        end
      end
    end
  end
end
