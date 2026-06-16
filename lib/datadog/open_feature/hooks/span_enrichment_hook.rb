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
      # Lifecycle:
      #   - `#finally` runs on every evaluation (success and error). It resolves
      #     the local root span off the active trace, lazily creates per-root
      #     accumulator state, and on the first capture for a trace subscribes to
      #     that trace's `span_before_finish` event.
      #   - When the local root span is about to finish, the accumulated tags are
      #     written via `span.set_tag` and the per-root state is deleted.
      #   - `#shutdown` clears all accumulated state (provider-close cleanup).
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
        # documentation; absent on older SDKs, in which case this is a no-op and
        # the SDK detects the hook via `respond_to?(:finally)`.
        include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

        # Returns true if the OpenFeature SDK supports hooks (>= 0.5.0).
        def self.available?
          !!defined?(::OpenFeature::SDK::Hooks::Hook)
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

        # Holds per-root-span accumulator state, keyed by the trace operation
        # (object identity). The map is bounded by the lifetime of in-flight
        # traces: state is deleted when the root span finishes, and cleared
        # wholesale on shutdown. There is no global subscription to leak.
        class AccumulatorStore
          def initialize
            @states = {}.compare_by_identity
          end

          def fetch(trace_op)
            @states[trace_op]
          end

          def fetch_or_create(trace_op)
            @states[trace_op] ||= Accumulator.new
          end

          def delete(trace_op)
            @states.delete(trace_op)
          end

          def clear
            @states.clear
          end
        end

        def initialize(accumulator_store)
          @store = accumulator_store
          @subscribed = {}.compare_by_identity
        end

        # OpenFeature finally hook: runs on every evaluation. Never raises — flag
        # evaluation must not be broken by enrichment (Pattern D).
        def finally(hook_context:, evaluation_details:, **_opts)
          store = @store
          return unless store

          trace_op = Datadog::Tracing.active_trace
          return unless trace_op

          metadata = evaluation_details.flag_metadata
          metadata = {} unless metadata.is_a?(Hash)
          serial_id = metadata[METADATA_SERIAL_ID]
          do_log = metadata[METADATA_DO_LOG] || false
          targeting_key = hook_context.evaluation_context&.targeting_key
          variant = evaluation_details.variant

          if serial_id.nil?
            if variant.nil? || (variant.respond_to?(:empty?) && variant.empty?)
              # Runtime default: detected by a missing variant (never a reason enum).
              state_for(trace_op).add_default(hook_context.flag_key, evaluation_details.value)
            end
          else
            state = state_for(trace_op)
            state.add_serial_id(serial_id)
            state.add_subject(targeting_key, serial_id) if do_log && targeting_key
          end
        rescue => e
          Datadog.logger.debug { "Error capturing span enrichment: #{e.class}: #{e.message}" }
        end

        # Provider-close cleanup: drop all accumulated state. Per-trace
        # subscriptions die with their trace operations, so there is nothing
        # else to unsubscribe.
        def shutdown
          @store&.clear
          @subscribed.clear
        end

        private

        # Lazily create the per-root state and, on first capture for a trace,
        # subscribe to that trace's span lifecycle so we can write tags when the
        # local root span finishes.
        def state_for(trace_op)
          state = @store.fetch_or_create(trace_op)
          subscribe_root_finish(trace_op) unless @subscribed[trace_op]
          state
        end

        def subscribe_root_finish(trace_op)
          events = trace_op.send(:events)
          # `span_before_finish` fires `(span_op, trace_op)` while the span can
          # still be enriched (before it is finalized into an immutable Span).
          events.span_before_finish.subscribe do |span_op, finishing_trace_op|
            write_tags_on_root(span_op, finishing_trace_op)
          end
          @subscribed[trace_op] = true
        rescue => e
          Datadog.logger.debug { "Error subscribing span enrichment: #{e.class}: #{e.message}" }
        end

        def write_tags_on_root(span_op, trace_op)
          # `span_before_finish` fires for EVERY span in the trace, and in any
          # nested trace the child spans finish before the local root. Only the
          # local root's finish may write tags AND clean up per-trace state:
          # cleaning up on a child finish would wipe the accumulator before the
          # root is written (CR-01). The cleanup therefore lives inside this
          # root-only branch, never in an unconditional `ensure` that would also
          # run for child finishes.
          return unless span_op.equal?(trace_op.send(:root_span))

          begin
            state = @store.fetch(trace_op)
            state.to_span_tags.each { |key, value| span_op.set_tag(key, value) if value } if state&.has_data?
          ensure
            # Delete only on the local root span's finish (mirrors the Node
            # reference's `spanStates.delete(span)` and the Python sibling's
            # `_on_span_finish` pop). A child finish never reaches here.
            @store.delete(trace_op)
            @subscribed.delete(trace_op)
          end
        rescue => e
          Datadog.logger.debug { "Error writing span enrichment tags: #{e.class}: #{e.message}" }
        end
      end
    end
  end
end
