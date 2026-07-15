# frozen_string_literal: true

require_relative 'span_enrichment_hook/codec'
require_relative 'span_enrichment_hook/span_enrichment_state'
require_relative 'span_enrichment_hook/span_enrichment_state_store'

module Datadog
  module OpenFeature
    module Hooks
      # Captures feature-flag evaluation metadata and writes contract-conformant
      # `ffe_*` tags onto the local root APM span when it finishes.
      #
      # The wire format is a fixed cross-SDK contract. The encoding (ULEB128
      # delta-varint + base64), the per-trace aggregation limits, the runtime-default
      # detection (missing variant) and the SHA256 subject hashing must be
      # reproduced exactly so the backend decodes tags identically regardless of
      # which language SDK emitted them.
      #
      # Dispatch:
      #   Enrichment is driven DIRECTLY from `Provider#evaluate` (see `#capture`),
      #   not through an OpenFeature hook. This is the only path that works on
      #   every supported SDK version, so the capture happens on the provider
      #   evaluation thread rather than a hook callback.
      #
      # Lifecycle:
      #   - `#capture` runs on every evaluation. It resolves the local root span
      #     off the active trace, lazily creates the per-root `SpanEnrichmentState`,
      #     and on the first capture for a trace subscribes to that trace's
      #     `span_before_finish` event. The subscription closure captures the
      #     state strongly and is held by `trace_op.events`, so the state lives
      #     exactly as long as the trace operation (the weak store key) — when the
      #     trace is GC'd both die together (no leak even if the root never finishes).
      #   - When the local root span is about to finish, the accumulated tags are
      #     written via `span.set_tag` and the per-root state is deleted.
      #   - `#shutdown` clears all accumulated state (provider-close cleanup).
      #
      # Thread-safety:
      #   Concurrent evaluations (on different threads) can target the same active
      #   trace. The GVL does NOT make the compound operations here safe
      #   (fetch-or-create, subscribe-once, mutate-while-encoding), so all store /
      #   subscription / state access is serialized through a single
      #   `Mutex`, and the finish-time encode takes the snapshot under that lock.
      #
      # When the gate is off the hook is never constructed (see
      # `Component#create_span_enrichment_hook`), so there is zero idle per-span
      # overhead.
      class SpanEnrichmentHook
        # Fixed cross-SDK contract limits. No env-var knobs.
        MAX_SERIAL_IDS = 200
        MAX_SUBJECTS = 10
        MAX_EXPERIMENTS_PER_SUBJECT = 20
        MAX_DEFAULTS = 5
        MAX_DEFAULT_VALUE_LENGTH = 64

        TAG_FLAGS_ENC = 'ffe_flags_enc'
        TAG_SUBJECTS_ENC = 'ffe_subjects_enc'
        TAG_RUNTIME_DEFAULTS = 'ffe_runtime_defaults'

        def initialize(span_enrichment_state_store, logger:)
          @store = span_enrichment_state_store
          @mutex = Mutex.new
          @closed = false
          @logger = logger
        end

        # Direct dispatch from the Datadog provider evaluation path. Takes only
        # primitives so it does not depend on any OpenFeature SDK object shape and
        # works on every supported SDK version. Never raises — flag evaluation and
        # the trace pipeline must not be broken by enrichment.
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
              if variant.nil? || variant.empty?
                # Runtime default: detected by a missing variant (never a reason enum).
                state_for(trace_op).add_default(flag_key, value)
              end
            else
              state = state_for(trace_op)
              state.add_serial_id(serial_id)
              # Skip empty targeting keys: SHA256('') would collide every
              # anonymous/missing subject under one bogus hash, corrupting
              # subject-level attribution.
              state.add_subject(targeting_key, serial_id) if do_log && targeting_key && !targeting_key.empty?
            end
          end
        rescue => e
          @logger.debug { "Error capturing span enrichment: #{e.class}: #{e.message}" }
        end

        # Provider-close cleanup: mark the hook closed and drop all accumulated
        # state. A trace that already subscribed still holds its state via
        # the `span_before_finish` closure, so the closed flag (checked in
        # `write_tags_on_root`) is what actually prevents a stale write after
        # shutdown. Per-trace subscriptions die with their trace operations, so
        # there is nothing else to unsubscribe.
        def shutdown
          @mutex.synchronize do
            @closed = true
            @store.clear!
          end
        end

        private

        # Lazily create the per-root state and, on first capture for a trace,
        # subscribe to that trace's span lifecycle so we can write tags when the
        # local root span finishes. MUST be called with `@mutex` held.
        def state_for(trace_op)
          state = @store[trace_op]
          return state if state

          state = SpanEnrichmentState.new
          @store[trace_op] = state
          subscribe_root_finish(trace_op, state)
          state
        end

        # MUST be called with `@mutex` held. The subscription closure captures
        # `state` strongly; since the closure is retained by
        # `trace_op.events`, this keeps the WeakMap value alive for the trace's
        # lifetime (and lets both be collected together when the trace is GC'd).
        def subscribe_root_finish(trace_op, state)
          events = trace_op.send(:events)
          # `span_before_finish` fires `(span_op, trace_op)` while the span can
          # still be enriched (before it is finalized into an immutable Span).
          # The block is the tracer-callback boundary and runs long after
          # `#capture` returns, so it rescues on its own — enrichment must never
          # raise into the trace pipeline. (Errors setting up the subscription
          # here propagate to `#capture`'s rescue, since this runs under it.)
          events.span_before_finish.subscribe do |span_op, finishing_trace_op|
            # `span_before_finish` fires for EVERY span in the trace, and in any
            # nested trace the child spans finish before the local root. Only the
            # local root's finish may write tags AND clean up per-trace state:
            # acting on a child finish would wipe the state before the root
            # is written. Guard here so `write_tags_on_root` (and its cleanup) only
            # ever runs for the local root.
            next unless span_op.equal?(finishing_trace_op.send(:root_span))

            write_tags_on_root(span_op, finishing_trace_op, state)
          rescue => e
            @logger.debug { "Error writing span enrichment tags: #{e.class}: #{e.message}" }
          end
        end

        def write_tags_on_root(span_op, trace_op, state)
          # Snapshot the tags under the lock so a concurrent `#capture` on another
          # thread cannot mutate the state's Sets/Hashes while we encode.
          tags = @mutex.synchronize do
            # After shutdown the store is cleared, but this trace's subscription
            # closure still holds the state; skip the write so a provider
            # close/reconfigure never emits stale `ffe_*` tags on an open trace.
            if @closed || !state.has_data?
              {}
            else
              state.to_span_tags
            end
          ensure
            # The caller only invokes this on the local root's finish, so cleanup
            # runs exactly once per trace. In an `ensure` so abandoned state is
            # still freed if encoding ever raises.
            @store.delete(trace_op)
          end

          tags.each { |key, value| span_op.set_tag(key, value) }
        end
      end
    end
  end
end
