# frozen_string_literal: true

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
      # - Context pruning: 256 fields / 256 chars (matches flageval-worker backend limits)
      class Aggregator
        MAX_CONTEXT_FIELDS = 256
        MAX_FIELD_LENGTH = 256
        MAX_CONTEXT_DEPTH = 32

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
          runtime_default: nil
        )
          runtime_default = variant.nil? if runtime_default.nil?
          runtime_default = !!runtime_default

          # Normalize nil/empty strings
          variant = variant.to_s
          allocation_key = allocation_key.to_s
          error_message = error_message.to_s
          targeting_key = targeting_key.to_s

          # Context pruning + canonical key (see prune_context and canonical_context_key).
          # Runs in the background writer so caller eval threads do not pay the flatten/prune cost.
          pruned_context = prune_context(attrs)
          context_key = canonical_context_key(pruned_context)

          full_key = [flag_key, variant, allocation_key, runtime_default, error_message, targeting_key, context_key]
          evaluation_time_ms = eval_time_ms.to_i

          @mutex.synchronize do
            # --- Full tier ---
            if (entry = @full[full_key])
              observe(entry, evaluation_time_ms)
              return
            end

            per_flag_count = @per_flag_full[flag_key]
            if per_flag_count >= @per_flag_cap
              add_to_degraded(flag_key, variant, allocation_key, runtime_default, error_message, evaluation_time_ms)
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
                context_attrs: pruned_context,
              )
              @full[full_key] = entry
              @global_count += 1
            else
              # Route to degraded tier
              add_to_degraded(flag_key, variant, allocation_key, runtime_default, error_message, evaluation_time_ms)
            end
          end
        end

        # Flush aggregation maps, reset state, return snapshot.
        # Returns { full: Hash, degraded: Hash, dropped_degraded_overflow: Integer }.
        # The overflow count is included in the snapshot so the caller can EMIT it before it is
        # reset — the count is never reset-without-emit (backpressure stays observable).
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

        # Prune context: keep first MAX_CONTEXT_FIELDS fields (sorted), skip string values >256 chars.
        # Keys are sorted before pruning to ensure deterministic subset selection.
        def prune_context(attrs)
          self.class.prune_context(attrs)
        end

        def self.prune_context(attrs)
          flattened_context = flatten_context(attrs)
          return {} if flattened_context.empty?

          pruned_context = {}
          count = 0
          flattened_context.keys.sort.each do |key|
            break if count >= MAX_CONTEXT_FIELDS

            value = flattened_context[key]
            # Skip oversized string values (mirrors flageval-worker pruning behavior).
            next if value.is_a?(String) && value.length > MAX_FIELD_LENGTH

            pruned_context[key] = value
            count += 1
          end
          pruned_context
        end

        def self.flatten_context(attrs)
          return {} unless attrs.is_a?(Hash) && !attrs.empty?

          flattened_context = {}
          seen = {attrs.object_id => true}
          attrs.each do |key, value|
            flatten_value(key.to_s, value, flattened_context, seen, 0)
          end
          flattened_context
        end

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

        def self.flatten_value(prefix, value, output, seen, depth)
          return if depth > MAX_CONTEXT_DEPTH

          case value
          when Hash
            object_id = value.object_id
            return if seen[object_id]

            seen[object_id] = true
            value.each do |key, child_value|
              flatten_value("#{prefix}.#{key}", child_value, output, seen, depth + 1)
            end
            seen.delete(object_id)
          when Array
            object_id = value.object_id
            return if seen[object_id]

            seen[object_id] = true
            value.each_with_index do |child_value, index|
              flatten_value("#{prefix}.#{index}", child_value, output, seen, depth + 1)
            end
            seen.delete(object_id)
          else
            output[prefix] = value unless value.nil?
          end
        end
        private_class_method :flatten_value

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

        def new_entry(evaluation_time_ms, runtime_default:, error_message: nil, targeting_key: nil, context_attrs: nil)
          {
            count: 1,
            first_evaluation: evaluation_time_ms,
            last_evaluation: evaluation_time_ms,
            runtime_default: runtime_default,
            error_message: error_message,
            targeting_key: targeting_key,
            context_attrs: context_attrs,
          }
        end

        def observe(entry, evaluation_time_ms)
          entry[:count] += 1
          entry[:first_evaluation] = evaluation_time_ms if evaluation_time_ms < entry[:first_evaluation]
          entry[:last_evaluation] = evaluation_time_ms if evaluation_time_ms > entry[:last_evaluation]
        end

        def add_to_degraded(flag_key, variant, allocation_key, runtime_default, error_message, evaluation_time_ms)
          degraded_key = [flag_key, variant, allocation_key, runtime_default, error_message]

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

          # Degraded entry omits targeting_key + context_attrs (schema omitempty fields)
          @degraded[degraded_key] = new_entry(
            evaluation_time_ms,
            runtime_default: runtime_default,
            error_message: error_message,
          )
        end
      end
    end
  end
end
