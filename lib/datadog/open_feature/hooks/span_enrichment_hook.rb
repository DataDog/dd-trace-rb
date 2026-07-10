# frozen_string_literal: true

require 'set'
require 'json'
require 'digest'
require 'base64'

module Datadog
  module OpenFeature
    module Hooks
      # Captures feature-flag evaluation metadata and writes contract-conformant
      # `ffe_*` tags onto the local root APM span when it finishes.
      #
      # This is the Ruby port of the frozen Node.js reference
      # (`dd-trace-js#8343`). The encoding (ULEB128 delta-varint + base64), the
      # accumulator limits, the runtime-default detection (missing variant) and
      # the SHA256 subject hashing are reproduced exactly so that the backend /
      # Trino decode and the parametric system-tests assertions stay in parity.
      #
      # Dispatch:
      #   The capture is driven DIRECTLY from `Provider#evaluate` (see
      #   `#capture`), not via the OpenFeature `finally` hook. The supported
      #   OpenFeature Ruby SDK versions (>= 0.3.1, the appraisal minimum) do NOT
      #   dispatch provider/client hooks at all — `Client#fetch_details` calls the
      #   provider and never invokes any hook — so relying on `finally` would
      #   silently emit no `ffe_*` tags even with the gate on. `#finally` is kept
      #   as a thin, idempotent delegate so that a future SDK which DOES dispatch
      #   hooks still works (the Set/Hash accumulators dedupe re-capture).
      #
      # Lifecycle:
      #   - `#capture` runs on every evaluation. It resolves the local root span
      #     off the active trace, lazily creates per-root accumulator state, and
      #     on the first capture for a trace subscribes to that trace's
      #     `span_before_finish` event. The subscription closure captures the
      #     accumulator strongly and is held by `trace_op.events`, so the
      #     accumulator lives exactly as long as the trace operation (the weak
      #     store key) — when the trace is GC'd both die together (no leak even
      #     if the root never finishes).
      #   - When the local root span is about to finish, the accumulated tags are
      #     written via `span.set_tag` and the per-root state is deleted.
      #   - `#shutdown` clears all accumulated state (provider-close cleanup).
      #
      # Thread-safety:
      #   Concurrent evaluations (on different threads) can target the same active
      #   trace. The GVL does NOT make the compound operations here safe
      #   (fetch-or-create, subscribe-once, mutate-while-encoding), so all store /
      #   subscription / accumulator access is serialized through a single
      #   `Mutex`, and the finish-time encode takes the snapshot under that lock.
      #
      # When the gate is off the hook is never constructed (see
      # `Component#create_span_enrichment_hook`), so there is zero idle per-span
      # overhead (DG-005).
      class SpanEnrichmentHook
        # Frozen contract limits — match the Node reference exactly. No env-var
        # knobs.
        MAX_SERIAL_IDS = 200
        MAX_SUBJECTS = 10
        MAX_EXPERIMENTS_PER_SUBJECT = 20
        MAX_DEFAULTS = 5
        MAX_DEFAULT_VALUE_LENGTH = 64

        TAG_FLAGS_ENC = 'ffe_flags_enc'
        TAG_SUBJECTS_ENC = 'ffe_subjects_enc'
        TAG_RUNTIME_DEFAULTS = 'ffe_runtime_defaults'

        METADATA_SERIAL_ID = '__dd_split_serial_id'
        METADATA_DO_LOG = '__dd_do_log'

        # Include the Hook module if available (SDK >= 0.5.0) for interface
        # documentation; absent on older SDKs. Note that even when present the
        # SDK does not dispatch the hook (see the class comment) — enrichment is
        # driven from `#capture` via the provider evaluation path.
        include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

        # Always available: enrichment no longer depends on SDK hook dispatch.
        # Retained for symmetry with the other hooks' `available?` and the
        # component gate, but the span-enrichment path works on every supported SDK.
        def self.available?
          true
        end

        # Pure encoding/crypto helpers. Ported verbatim from the frozen Node
        # reference; uses only Ruby stdlib (no new dependencies).
        module Codec
          module_function

          # ULEB128: 7 bits per byte, MSB set marks continuation.
          # The buffer MUST be binary (ASCII-8BIT): `String#<<` with an Integer on a
          # UTF-8 string appends a Unicode *codepoint*, so any byte >= 0x80 would be
          # re-encoded as a 2-byte UTF-8 sequence and corrupt the varint (e.g. serial
          # 2312 -> bytes 88 12, but UTF-8 would emit C2 88 12 = 296002 on decode).
          def encode_varint(value)
            bytes = (+'').b
            while value > 0x7F
              bytes << ((value & 0x7F) | 0x80)
              value >>= 7
            end
            bytes << (value & 0x7F)
            bytes
          end

          # Encode a Set of serial ids as base64(ULEB128 delta-varint).
          # Empty set -> empty string (the caller omits the tag).
          def encode_delta_varint(serial_ids)
            sorted = serial_ids.to_a.sort
            return '' if sorted.empty?

            bytes = (+'').b
            prev = 0
            sorted.each do |id|
              bytes << encode_varint(id - prev)
              prev = id
            end
            Base64.strict_encode64(bytes)
          end

          # Lowercase hex SHA256 of the targeting key (privacy contract DG-003).
          def hash_targeting_key(targeting_key)
            Digest::SHA256.hexdigest(targeting_key)
          end
        end

        # Per-root-span accumulator. Enforces the frozen limits, dedupes serial
        # ids structurally via a Set, and renders the three `ffe_*` tag shapes.
        #
        # Not internally synchronized: every method is only ever called while the
        # owning `SpanEnrichmentHook`'s mutex is held (capture, encode, cleanup),
        # so the accumulator stays a plain object and the lock provides the
        # consistent snapshot at encode time.
        class Accumulator
          def initialize
            @serial_ids = Set.new
            @subjects = {} # sha256hex => Set<int>
            @defaults = {} # flagKey => String
          end

          def add_serial_id(serial_id)
            return if @serial_ids.size >= MAX_SERIAL_IDS && !@serial_ids.include?(serial_id)

            @serial_ids.add(serial_id)
          end

          def add_subject(targeting_key, serial_id)
            hashed = Codec.hash_targeting_key(targeting_key)
            existing = @subjects[hashed]

            if existing
              return if existing.size >= MAX_EXPERIMENTS_PER_SUBJECT && !existing.include?(serial_id)

              existing.add(serial_id)
            elsif @subjects.size >= MAX_SUBJECTS
              nil
            else
              @subjects[hashed] = Set[serial_id]
            end
          end

          def add_default(flag_key, value)
            return if @defaults.key?(flag_key) # first-wins
            return if @defaults.size >= MAX_DEFAULTS

            value_str = value.is_a?(String) ? value : JSON.generate(value)
            # `String#[]` slices by codepoint, so truncation never splits a
            # multibyte UTF-8 character (frozen-contract: 64 chars, UTF-8-safe).
            value_str = value_str[0...MAX_DEFAULT_VALUE_LENGTH] if value_str.length > MAX_DEFAULT_VALUE_LENGTH
            @defaults[flag_key] = value_str.to_s
          end

          # Subjects are intentionally not checked: a subject is only ever added
          # alongside a serial id, so serial ids cover that case.
          def has_data?
            !@serial_ids.empty? || !@defaults.empty?
          end

          def to_span_tags
            tags = {}
            tags[TAG_FLAGS_ENC] = Codec.encode_delta_varint(@serial_ids) unless @serial_ids.empty?

            unless @subjects.empty?
              encoded_subjects = {}
              @subjects.each { |hashed, ids| encoded_subjects[hashed] = Codec.encode_delta_varint(ids) }
              tags[TAG_SUBJECTS_ENC] = JSON.generate(encoded_subjects)
            end

            tags[TAG_RUNTIME_DEFAULTS] = JSON.generate(@defaults) unless @defaults.empty?

            tags
          end
        end

        # Holds per-root-span accumulator state, keyed WEAKLY by the trace
        # operation (object identity). Using `ObjectSpace::WeakMap` means an
        # abandoned trace (root span never finishes) cannot pin its accumulator:
        # once the trace operation is unreachable the entry is collected. The
        # accumulator (the WeakMap *value*, which `WeakMap` would otherwise also
        # collect once no strong ref remains) is kept alive for the trace's
        # lifetime by the `span_before_finish` subscription closure, which is held
        # by `trace_op.events`. So state lives exactly as long as the trace and
        # dies with it.
        #
        # All access is serialized by the owning hook's mutex; the WeakMap itself
        # is not thread-safe under concurrent mutation.
        class AccumulatorStore
          def initialize
            @states = ObjectSpace::WeakMap.new # steep:ignore UnknownConstant
          end

          def fetch(trace_op)
            @states[trace_op]
          end

          # Returns [accumulator, created?]. The caller subscribes (under lock)
          # only on first creation so the subscription closure can capture the
          # accumulator and keep it alive for the trace's lifetime.
          def fetch_or_create(trace_op)
            existing = @states[trace_op]
            return [existing, false] if existing

            accumulator = Accumulator.new
            @states[trace_op] = accumulator
            [accumulator, true]
          end

          def delete(trace_op)
            # `ObjectSpace::WeakMap` exposes no per-key delete; overwrite the slot
            # with nil so a stale entry is never re-read after the root finishes.
            # The slot itself is reclaimed when the trace operation is collected.
            @states[trace_op] = nil
          end

          def clear
            @states = ObjectSpace::WeakMap.new # steep:ignore UnknownConstant
          end
        end

        def initialize(accumulator_store)
          @store = accumulator_store
          @mutex = Mutex.new
        end

        # Direct dispatch from the Datadog provider evaluation path. Takes only
        # primitives so it does not depend on any OpenFeature SDK object shape and
        # works on every supported SDK version. Never raises — flag evaluation and
        # the trace pipeline must not be broken by enrichment (Pattern D).
        #
        # @param flag_key [String] the evaluated flag key
        # @param variant [String, nil] the resolved variant (nil/empty => runtime default)
        # @param value [Object] the resolved value (used for runtime-default capture)
        # @param serial_id [Integer, nil] the split serial id, when assigned
        # @param do_log [Boolean] whether logging/exposure is authorized for this subject
        # @param targeting_key [String, nil] the raw targeting key (hashed before emit)
        def capture(flag_key:, variant:, value:, serial_id:, do_log:, targeting_key:)
          trace_op = Datadog::Tracing.active_trace
          return unless trace_op

          @mutex.synchronize do
            if serial_id.nil?
              if variant.nil? || (variant.respond_to?(:empty?) && variant.empty?)
                # Runtime default: detected by a missing variant (never a reason enum).
                state_for(trace_op).add_default(flag_key, value)
              end
            else
              state = state_for(trace_op)
              state.add_serial_id(serial_id)
              state.add_subject(targeting_key, serial_id) if do_log && targeting_key
            end
          end
        rescue => e
          Datadog.logger.debug { "Error capturing span enrichment: #{e.class}: #{e.message}" }
        end

        # OpenFeature `finally` hook: kept for forward compatibility with a future
        # SDK that actually dispatches provider hooks. Idempotent with `#capture`
        # (Set/Hash accumulators dedupe). Never raises.
        def finally(hook_context:, evaluation_details:, **_opts)
          metadata = evaluation_details.flag_metadata
          metadata = {} unless metadata.is_a?(Hash)

          capture(
            flag_key: hook_context.flag_key,
            variant: evaluation_details.variant,
            value: evaluation_details.value,
            serial_id: metadata[METADATA_SERIAL_ID],
            do_log: metadata[METADATA_DO_LOG] || false,
            targeting_key: hook_context.evaluation_context&.targeting_key,
          )
        rescue => e
          Datadog.logger.debug { "Error capturing span enrichment (finally): #{e.class}: #{e.message}" }
        end

        # Provider-close cleanup: drop all accumulated state. Per-trace
        # subscriptions die with their trace operations, so there is nothing
        # else to unsubscribe.
        def shutdown
          @mutex.synchronize { @store&.clear }
        end

        private

        # Lazily create the per-root state and, on first capture for a trace,
        # subscribe to that trace's span lifecycle so we can write tags when the
        # local root span finishes. MUST be called with `@mutex` held.
        def state_for(trace_op)
          state, created = @store.fetch_or_create(trace_op)
          subscribe_root_finish(trace_op, state) if created
          state
        end

        # MUST be called with `@mutex` held. The subscription closure captures
        # `accumulator` strongly; since the closure is retained by
        # `trace_op.events`, this keeps the WeakMap value alive for the trace's
        # lifetime (and lets both be collected together when the trace is GC'd).
        def subscribe_root_finish(trace_op, accumulator)
          events = trace_op.send(:events)
          # `span_before_finish` fires `(span_op, trace_op)` while the span can
          # still be enriched (before it is finalized into an immutable Span).
          events.span_before_finish.subscribe do |span_op, finishing_trace_op|
            write_tags_on_root(span_op, finishing_trace_op, accumulator)
          end
        rescue => e
          Datadog.logger.debug { "Error subscribing span enrichment: #{e.class}: #{e.message}" }
        end

        def write_tags_on_root(span_op, trace_op, accumulator)
          # `span_before_finish` fires for EVERY span in the trace, and in any
          # nested trace the child spans finish before the local root. Only the
          # local root's finish may write tags AND clean up per-trace state:
          # cleaning up on a child finish would wipe the accumulator before the
          # root is written (CR-01). The cleanup therefore lives inside this
          # root-only branch, never in an unconditional `ensure` that would also
          # run for child finishes.
          return unless span_op.equal?(trace_op.send(:root_span))

          # Snapshot the tags under the lock so a concurrent `#capture` on another
          # thread cannot mutate the accumulator's Sets/Hashes while we encode.
          tags = @mutex.synchronize do
            snapshot = accumulator.has_data? ? accumulator.to_span_tags : {}
            snapshot
          ensure
            # Delete only on the local root span's finish (mirrors the Node
            # reference's `spanStates.delete(span)` and the Python sibling's
            # `_on_span_finish` pop). A child finish never reaches here. In an
            # `ensure` so abandoned state is still freed if encoding ever raises.
            @store.delete(trace_op)
          end

          tags.each { |key, value| span_op.set_tag(key, value) if value }
        rescue => e
          Datadog.logger.debug { "Error writing span enrichment tags: #{e.class}: #{e.message}" }
        end
      end
    end
  end
end
