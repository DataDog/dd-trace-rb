# frozen_string_literal: true

module Datadog
  module OpenFeature
    module FlagEvaluation
      # Two-tier aggregation for EVP flagevaluation events.
      #
      # Two-tier design:
      # - full-tier  key: (flag_key, variant, allocation_key, reason, targeting_key, canonical_context_key)
      # - degraded-tier key: (flag_key, variant, allocation_key, reason) — exactly OTel cardinality
      # - Drop-and-count when degraded tier is full (no ultra-degraded tier)
      # - canonical_context_key: sorted type-tagged length-delimited encoding (no hash digest)
      # - Caps: globalCap=131_072 / perFlagCap=10_000 / degradedCap=32_768
      # - Context pruning: 256 fields / 256 chars (matches flageval-worker backend limits)
      class Aggregator
        MAX_CONTEXT_FIELDS = 256
        MAX_FIELD_LENGTH = 256

        DEFAULT_GLOBAL_CAP = 131_072
        DEFAULT_PER_FLAG_CAP = 10_000
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
          # per-flag full-bucket count for perFlagCap enforcement
          @per_flag_full = Hash.new(0)
          @global_count = 0
          @dropped_degraded_overflow = 0
        end

        # Record one evaluation event. Thread-safe. Called from the hook's finally stage.
        # All aggregation is done here — the hook itself only calls record.
        def record(flag_key:, variant:, allocation_key:, reason:, targeting_key:, eval_time_ms:, attrs:)
          # Runtime default: primary signal is absent/nil variant (not reason alone)
          runtime_default = variant.nil?

          # Normalize nil/empty strings
          variant = variant.to_s
          allocation_key = allocation_key.to_s
          reason = reason.to_s
          targeting_key = targeting_key.to_s

          # Context pruning + canonical key (see prune_context and canonical_context_key)
          pruned = prune_context(attrs)
          ctx_key = canonical_context_key(pruned)

          full_key = [flag_key, variant, allocation_key, reason, targeting_key, ctx_key]
          eval_ms = eval_time_ms.to_i

          @mutex.synchronize do
            # --- Full tier ---
            if (e = @full[full_key])
              observe(e, eval_ms)
              return
            end

            # Check caps before adding new full bucket
            full_ok = @global_count < @global_cap &&
              @per_flag_full[flag_key] < @per_flag_cap

            if full_ok
              e = new_entry(eval_ms, runtime_default: runtime_default, targeting_key: targeting_key, context_attrs: pruned)
              @full[full_key] = e
              @per_flag_full[flag_key] += 1
              @global_count += 1
            else
              # Route to degraded tier
              add_to_degraded(flag_key, variant, allocation_key, reason, eval_ms, runtime_default)
            end
          end
        end

        # Flush aggregation maps, reset state, return snapshot.
        # Returns { full: Hash, degraded: Hash, dropped_degraded_overflow: Integer }.
        # The overflow count is included in the snapshot so the caller can EMIT it before it is
        # reset — the count is never reset-without-emit (backpressure stays observable).
        def flush_and_reset
          @mutex.synchronize do
            full_snap = @full
            degraded_snap = @degraded
            dropped_snap = @dropped_degraded_overflow

            @full = {}
            @degraded = {}
            @per_flag_full = Hash.new(0)
            @global_count = 0
            @dropped_degraded_overflow = 0

            {full: full_snap, degraded: degraded_snap, dropped_degraded_overflow: dropped_snap}
          end
        end

        # Prune context: keep first MAX_CONTEXT_FIELDS fields (sorted), skip string values >256 chars.
        # Keys are sorted before pruning to ensure deterministic subset selection.
        def prune_context(attrs)
          return {} if attrs.nil? || attrs.empty?

          out = {}
          count = 0
          attrs.keys.sort.each do |k|
            break if count >= MAX_CONTEXT_FIELDS

            v = attrs[k]
            # Skip oversized string values (mirrors Go: worker.ts pruneFields behavior)
            next if v.is_a?(String) && v.length > MAX_FIELD_LENGTH

            out[k] = v
            count += 1
          end
          out
        end

        # Canonical context key: sorted type-tagged length-delimited encoding.
        # Each field is: 8-byte big-endian key length + key bytes + type-tag byte +
        #                8-byte big-endian value length + value bytes.
        # No hash digest — the key IS the full encoding (collision-free, no FNV).
        def canonical_context_key(attrs)
          return '' if attrs.nil? || attrs.empty?

          buf = String.new('', encoding: Encoding::BINARY)
          attrs.keys.sort.each do |k|
            v = attrs[k]
            buf << length_delimited(k.to_s)
            buf << context_value_bytes(v)
          end
          buf
        end

        private

        # Type tags matching Go reference (flagevaluation.go lines 741-752)
        CTX_TAG_STRING = 's'
        CTX_TAG_BOOL = 'b'
        CTX_TAG_INTEGER = 'i'
        CTX_TAG_FLOAT = 'f'
        CTX_TAG_OTHER = 'o'

        def context_value_bytes(v)
          tag, encoded = case v
          when String then [CTX_TAG_STRING, v.to_s]
          when TrueClass, FalseClass then [CTX_TAG_BOOL, v.to_s]
          when Integer then [CTX_TAG_INTEGER, v.to_s]
          when Float then [CTX_TAG_FLOAT, v.to_s]
          else [CTX_TAG_OTHER, v.to_s]
          end
          String.new(tag, encoding: Encoding::BINARY) + length_delimited(encoded)
        end

        # 8-byte big-endian length prefix + raw bytes. Unambiguous field boundary.
        def length_delimited(s)
          bytes = s.encode(Encoding::BINARY, invalid: :replace, undef: :replace)
          n = bytes.bytesize
          # Build 8-byte big-endian length
          len_bytes = String.new('', encoding: Encoding::BINARY)
          8.times { |i| len_bytes.prepend(((n >> (8 * i)) & 0xFF).chr(Encoding::BINARY)) }
          len_bytes + bytes
        end

        def new_entry(eval_ms, runtime_default:, targeting_key: nil, context_attrs: nil)
          {
            count: 1,
            first_evaluation: eval_ms,
            last_evaluation: eval_ms,
            runtime_default: runtime_default,
            targeting_key: targeting_key,
            context_attrs: context_attrs,
          }
        end

        def observe(entry, eval_ms)
          entry[:count] += 1
          entry[:first_evaluation] = eval_ms if eval_ms < entry[:first_evaluation]
          entry[:last_evaluation] = eval_ms if eval_ms > entry[:last_evaluation]
        end

        def add_to_degraded(flag_key, variant, allocation_key, reason, eval_ms, runtime_default)
          deg_key = [flag_key, variant, allocation_key, reason]

          if (e = @degraded[deg_key])
            observe(e, eval_ms)
            return
          end

          # New degraded bucket — check degradedCap (terminal tier)
          if @degraded.size >= @degraded_cap
            # Terminal tier full — drop and count (explicit overflow counter)
            @dropped_degraded_overflow += 1
            return
          end

          # Degraded entry omits targeting_key + context_attrs (schema omitempty fields)
          @degraded[deg_key] = new_entry(eval_ms, runtime_default: runtime_default)
        end
      end
    end
  end
end
