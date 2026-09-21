# frozen_string_literal: true

require "digest"

require_relative "aggregator"
require_relative "../ext"
require_relative "../../core/encoding"
require_relative "../../core/evp"
require_relative "../../core/utils/time"
require_relative "../../core/workers/async"

module Datadog
  module OpenFeature
    module FlagEvaluation
      # Background writer that drains the two-tier aggregation maps and POSTs
      # batches to /evp_proxy/v2/api/v2/flagevaluation every FLUSH_INTERVAL_SECONDS.
      #
      # The writer owns the aggregation cycle:
      #   1. Hook calls enqueue (non-blocking) — never aggregates inline.
      #   2. Background thread wakes, calls aggregator.record for each enqueued event, flushes.
      #   3. flush_once drains aggregation maps, builds payload, sends via transport.
      #
      # Thread model: MRI Ruby GIL — Mutex + ConditionVariable + SizedQueue + Thread.
      # The flush loop waits on a ConditionVariable (interruptible) rather than a bare
      # sleep, so #stop can wake the worker immediately and still drain + final-flush.
      class Writer
        include Core::Workers::Async::Thread

        FLUSH_INTERVAL_SECONDS = 10
        DRAIN_INTERVAL_SECONDS = 0.1
        SHUTDOWN_TIMEOUT_SECONDS = 5
        QUEUE_SIZE = 4_096
        MAX_DRAIN_EVENTS_PER_CYCLE = 1_024
        PAYLOAD_SIZE_LIMIT_BYTES = Core::EVP::PAYLOAD_SIZE_LIMIT_BYTES
        TELEMETRY_NAMESPACE = "tracers"
        ROWS_DROPPED_METRIC = "flagevaluation.rows.dropped"
        ROWS_DEGRADED_METRIC = "flagevaluation.rows.degraded"
        PAYLOAD_SPLITS_METRIC = "flagevaluation.payload.splits"
        CONTEXT_TRUNCATED_METRIC = "flagevaluation.context.truncated"

        REASON_QUEUE_OVERFLOW = "queue_overflow"
        REASON_DEGRADED_CAP = "degraded_cap"
        REASON_CARDINALITY_CAP = "cardinality_cap"
        REASON_PAYLOAD_LIMIT = "payload_limit"
        REASON_PRE_QUEUE_OVERFLOW = "pre_queue_overflow"
        REASON_SERIALIZATION_ERROR = "serialization_error"
        REASON_SNAPSHOT_ERROR = "snapshot_error"

        # Must equal OpenFeature::SDK::EvaluationContext::TARGETING_KEY. Duplicated as a
        # literal rather than referenced because the SDK is an optional dependency and
        # this file loads without it. If the two drift, the targeting key stops being
        # excluded from the context snapshot and lands in context.evaluation as raw PII,
        # so a spec asserts the equality.
        TARGETING_KEY_FIELD = "targeting_key"
        TARGETING_KEY_HASH_PREFIX = "sha256_"

        # Service context fields for the batch wrapper.
        attr_reader :service_context

        # Observable count of events dropped because the async hand-off queue was full.
        # Reset to 0 each flush after being emitted, mirroring the aggregator's overflow counter.
        attr_reader :dropped_queue_overflow

        def initialize(transport:, logger:, telemetry: nil)
          @transport = transport
          @logger = logger
          @telemetry = telemetry
          @aggregator = Aggregator.new
          @queue = SizedQueue.new(QUEUE_SIZE)
          @stop_mutex = Mutex.new
          @stop_cond = ConditionVariable.new
          @stopped = false
          @dropped_queue_overflow = 0
          @dropped_pre_queue_overflow = 0
          @context_truncated_counts = Hash.new(0)
          @context_snapshot_error_logged = false

          self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_RESTART

          @service_context = build_service_context
          start_background_thread
        end

        # Non-blocking enqueue from the finally hook. Drops + counts on overflow.
        def enqueue(
          flag_key:, eval_time_ms:, variant: nil, allocation_key: nil, error_message: nil,
          runtime_default: nil, targeting_key: nil, attrs: nil, observe_full_evaluation_data: false,
          **_event
        )
          start_background_thread if forked?

          # Avoid snapshot work when the queue is already full.
          if @queue.size >= QUEUE_SIZE
            @stop_mutex.synchronize { @dropped_pre_queue_overflow += 1 }
            return
          end

          observe_full_evaluation_data = observe_full_evaluation_data == true
          attrs = observe_full_evaluation_data ? snapshot_context(attrs) : nil
          bounded_event = {
            flag_key: snapshot_string(flag_key),
            variant: snapshot_string(variant),
            allocation_key: snapshot_string(allocation_key),
            error_message: normalized_error_code(error_message),
            runtime_default: runtime_default,
            targeting_key: snapshot_targeting_key(targeting_key),
            eval_time_ms: snapshot_integer(eval_time_ms),
            attrs: attrs,
            observe_full_evaluation_data: observe_full_evaluation_data,
          }
          @queue.push(bounded_event, true)
          @stop_mutex.synchronize { @stop_cond.signal }
          start_background_thread unless running?
        rescue ThreadError
          # Report queue backpressure on the next flush.
          @stop_mutex.synchronize { @dropped_queue_overflow += 1 }
        end

        # Stop the background thread and flush remaining events. Wakes the worker out of its
        # interruptible wait so the drain + final flush happen immediately (no up-to-10s delay).
        def stop
          @stop_mutex.synchronize do
            @stopped = true
            @stop_cond.broadcast
          end

          return true if join(SHUTDOWN_TIMEOUT_SECONDS)

          @logger.debug { "OpenFeature EVP: writer did not stop gracefully; terminating worker thread" }
          terminate
        end

        protected

        def after_fork
          @aggregator = Aggregator.new
          @queue = SizedQueue.new(QUEUE_SIZE)
          @stop_mutex = Mutex.new
          @stop_cond = ConditionVariable.new
          @stopped = false
          @dropped_queue_overflow = 0
          @dropped_pre_queue_overflow = 0
          @context_truncated_counts = Hash.new(0)
          @context_snapshot_error_logged = false
        end

        private

        def snapshot_context(attrs)
          return {} unless attrs.is_a?(Hash)

          snapshot, reasons = Aggregator.bounded_context_snapshot(attrs, excluded_key: TARGETING_KEY_FIELD)
          unless reasons.empty?
            @stop_mutex.synchronize { reasons.each { |reason| @context_truncated_counts[reason] += 1 } }
          end
          snapshot
        rescue => e
          # Context handling runs in the finally hook and must not interrupt flag evaluation.
          should_log = false
          @stop_mutex.synchronize do
            @context_truncated_counts[REASON_SNAPSHOT_ERROR] += 1
            unless @context_snapshot_error_logged
              @context_snapshot_error_logged = true
              should_log = true
            end
          end
          @logger.debug { "OpenFeature EVP: context snapshot error: #{e.class}" } if should_log
          {}
        end

        def build_service_context
          config = Datadog.configuration
          ctx = {"service" => snapshot_string(config.service) || ""}
          env = snapshot_string(config.env)
          version = snapshot_string(config.version)
          ctx["env"] = env if env && !env.empty?
          ctx["version"] = version if version && !version.empty?
          ctx
        end

        def snapshot_string(value)
          return unless value

          string = value.is_a?(String) ? value : value.to_s
          String.new(string).encode(Encoding::UTF_8, invalid: :replace, undef: :replace).freeze
        rescue
          # Unsupported caller values must not break flag evaluation.
          nil
        end

        def snapshot_targeting_key(value)
          return unless value.is_a?(String)

          string = String.new(value)
          return unless string.valid_encoding?

          string.encode!(Encoding::UTF_8)
          string.freeze
        rescue EncodingError
          nil
        end

        def snapshot_integer(value)
          integer = value.to_i
          integer.is_a?(Integer) ? integer : 0
        rescue
          0
        end

        def normalized_error_code(value)
          error_code = snapshot_string(value)
          # Preserve absence so evaluations without errors omit the error field.
          return error_code if !error_code || error_code.empty?
          return error_code if Ext::STANDARD_ERROR_CODES.include?(error_code)

          Ext::GENERAL
        end

        def start_background_thread
          perform
        end

        def perform
          last_flush = Core::Utils::Time.get_time

          loop do
            wait_for_next_cycle
            begin
              drain_queue
              now = Core::Utils::Time.get_time
              if stopped? || now - last_flush >= FLUSH_INTERVAL_SECONDS
                flush_once
                last_flush = now
              end
            rescue => e
              @logger.debug { "OpenFeature EVP: writer error: #{e.class}: #{e.message}" }
            end

            break if stopped?
          end

          # Final drain + flush on shutdown so queued events are not lost.
          begin
            drain_and_flush
          rescue => e
            @logger.debug { "OpenFeature EVP: writer final-flush error: #{e.class}: #{e.message}" }
          end
        end

        def stopped?
          @stop_mutex.synchronize { @stopped }
        end

        def wait_for_next_cycle
          @stop_mutex.synchronize do
            return if @stopped || !@queue.empty?

            @stop_cond.wait(@stop_mutex, DRAIN_INTERVAL_SECONDS)
          end
        end

        def drain_and_flush
          drain_queue(max_events: nil)
          flush_once
        end

        def drain_queue(max_events: MAX_DRAIN_EVENTS_PER_CYCLE)
          # Drain async queue into aggregator (background thread only).
          # Normal cycles are bounded so flush cadence cannot starve under sustained producers.
          drained = 0
          until @queue.empty?
            break if max_events && drained >= max_events

            begin
              event = @queue.pop(true)
              @aggregator.record(
                flag_key: event[:flag_key].to_s,
                variant: event[:variant],
                allocation_key: event[:allocation_key],
                targeting_key: event[:targeting_key],
                eval_time_ms: event[:eval_time_ms].to_i,
                attrs: event[:attrs],
                error_message: event[:error_message],
                runtime_default: event[:runtime_default],
                observe_full_evaluation_data: event[:observe_full_evaluation_data],
              )
              drained += 1
            rescue ThreadError
              break
            end
          end
          drained
        end

        def flush_once
          snapshot = @aggregator.flush_and_reset
          dropped_overflow = snapshot[:dropped_degraded_overflow].to_i
          dropped_queue = read_and_reset_dropped_queue_overflow
          dropped_pre_queue = read_and_reset_dropped_pre_queue_overflow
          context_truncated_counts = read_and_reset_context_truncated_counts

          emit_drop_counts(dropped_queue, dropped_overflow, dropped_pre_queue)
          context_truncated_counts.each do |reason, count|
            record_telemetry_count(CONTEXT_TRUNCATED_METRIC, count, reason: reason)
          end

          events = build_events(snapshot)
          record_telemetry_count(ROWS_DEGRADED_METRIC, snapshot[:degraded].values.sum { |entry| entry[:count].to_i }, reason: REASON_CARDINALITY_CAP)
          return if events.empty?

          send_payload_batches(events)
        rescue => e
          @logger.debug { "OpenFeature EVP: flush error: #{e.class}: #{e.message}" }
        end

        def read_and_reset_dropped_queue_overflow
          @stop_mutex.synchronize do
            count = @dropped_queue_overflow
            @dropped_queue_overflow = 0
            count
          end
        end

        def read_and_reset_dropped_pre_queue_overflow
          @stop_mutex.synchronize do
            count = @dropped_pre_queue_overflow
            @dropped_pre_queue_overflow = 0
            count
          end
        end

        def read_and_reset_context_truncated_counts
          @stop_mutex.synchronize do
            counts = @context_truncated_counts
            @context_truncated_counts = Hash.new(0)
            counts
          end
        end

        # Emit (log) the observable drop counts so backpressure is never silently lost.
        # Σ(emitted tier counts + these drops) == evaluations processed.
        def emit_drop_counts(dropped_queue, dropped_overflow, dropped_pre_queue)
          return if dropped_queue.zero? && dropped_overflow.zero? && dropped_pre_queue.zero?

          record_telemetry_count(ROWS_DROPPED_METRIC, dropped_pre_queue, reason: REASON_PRE_QUEUE_OVERFLOW)
          record_telemetry_count(ROWS_DROPPED_METRIC, dropped_queue, reason: REASON_QUEUE_OVERFLOW)
          record_telemetry_count(ROWS_DROPPED_METRIC, dropped_overflow, reason: REASON_DEGRADED_CAP)

          @logger.debug do
            "OpenFeature EVP: dropped events " \
              "pre_queue_overflow=#{dropped_pre_queue} " \
              "queue_overflow=#{dropped_queue} degraded_overflow=#{dropped_overflow}"
          end
        end

        # Build flagEvaluationEvent list from aggregation snapshot.
        def build_events(snapshot)
          flush_time_ms = (Core::Utils::Time.now.to_f * 1000).to_i
          events = []

          snapshot[:full].each do |key, entry|
            flag_key, variant, allocation_key, _runtime_default, _error_message, targeting_key, _ctx_key, _observe_full_evaluation_data = key
            event = build_event(
              flag_key: flag_key, variant: variant, allocation_key: allocation_key,
              targeting_key: targeting_key, entry: entry, flush_time_ms: flush_time_ms, tier: :full,
            )
            events << event
          end

          # Degraded rows omit targeting_key and context, so the policy is not a key dimension.
          snapshot[:degraded].each do |key, entry|
            flag_key, variant, allocation_key, _runtime_default, _error_dimension = key
            event = build_event(
              flag_key: flag_key, variant: variant, allocation_key: allocation_key,
              targeting_key: nil, entry: entry, flush_time_ms: flush_time_ms, tier: :degraded,
            )
            events << event
          end

          events
        end

        def build_event(
          flag_key:, variant:, allocation_key:, targeting_key:, entry:, flush_time_ms:, tier:
        )
          observe_full_evaluation_data = entry[:observe_full_evaluation_data]
          # @type var event: ::Hash[::String, any]
          event = {
            "timestamp" => flush_time_ms,
            "flag" => {"key" => flag_key},
            "first_evaluation" => entry[:first_evaluation],
            "last_evaluation" => entry[:last_evaluation],
            "evaluation_count" => entry[:count],
          }

          event["runtime_default_used"] = true if entry[:runtime_default]

          # EVP uses the normalized code as error.message and an aggregation dimension.
          error_message = entry[:error_message]
          if error_message && !error_message.empty?
            event["error"] = {"message" => error_message}
          end

          # variant + allocation are present in both tiers (omitempty per schema).
          event["variant"] = {"key" => variant} if variant && !variant.empty?
          event["allocation"] = {"key" => allocation_key} if allocation_key && !allocation_key.empty?

          # Full-tier additionally carries targeting_key and the truncated evaluation context;
          # the degraded tier omits both.
          if tier == :full
            unless targeting_key.nil?
              event["targeting_key"] =
                if targeting_key.empty? || observe_full_evaluation_data
                  targeting_key
                else
                  prefixed_targeting_key_digest(targeting_key)
                end
            end

            if observe_full_evaluation_data && entry[:context_attrs] && !entry[:context_attrs].empty?
              event["context"] = {"evaluation" => entry[:context_attrs]}
            end
          end

          event
        end

        # Encode to UTF-8 first so Ruby encodings do not change the digest.
        # Distinct from SpanEnrichmentHook::Codec.hash_targeting_key, which emits a
        # bare digest for a different wire format on the span track.
        def prefixed_targeting_key_digest(targeting_key)
          utf8 = targeting_key.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
          TARGETING_KEY_HASH_PREFIX + Digest::SHA256.hexdigest(utf8)
        end

        def send_payload_batches(events)
          context_json = Core::Encoding::JSONEncoder.encode(@service_context)
          payload_prefix = "{\"context\":#{context_json},\"flagEvaluations\":["
          payload_suffix = "]}"
          base_payload_size = payload_prefix.bytesize + payload_suffix.bytesize

          batch = []
          batch_size = base_payload_size
          dropped_oversized = 0
          dropped_serialization = 0
          payload_limit_degraded = 0
          payload_splits = 0

          events.each do |event|
            begin
              encoded_event = encoded_event_for_payload(event, base_payload_size)
            rescue => e
              # Keep one malformed event from discarding the complete flush snapshot.
              dropped_serialization += event_count(event)
              @logger.debug { "OpenFeature EVP: dropped event serialization_error=#{e.class}" }
              next
            end
            unless encoded_event
              dropped_oversized += event_count(event)
              next
            end

            event_hash, event_size, degraded_for_payload_limit = encoded_event
            payload_limit_degraded += event_count(event_hash) if degraded_for_payload_limit
            separator_size = batch.empty? ? 0 : 1

            if !batch.empty? && batch_size + separator_size + event_size > self.class::PAYLOAD_SIZE_LIMIT_BYTES
              send_payload_batch(batch)
              batch = []
              batch_size = base_payload_size
              separator_size = 0
              payload_splits += 1
            end

            batch << event_hash
            batch_size += separator_size + event_size
          end

          send_payload_batch(batch) unless batch.empty?
          record_telemetry_count(ROWS_DEGRADED_METRIC, payload_limit_degraded, reason: REASON_PAYLOAD_LIMIT)
          record_telemetry_count(ROWS_DROPPED_METRIC, dropped_oversized, reason: REASON_PAYLOAD_LIMIT)
          record_telemetry_count(ROWS_DROPPED_METRIC, dropped_serialization, reason: REASON_SERIALIZATION_ERROR)
          record_telemetry_count(PAYLOAD_SPLITS_METRIC, payload_splits)
          @logger.debug { "OpenFeature EVP: dropped events payload_oversize=#{dropped_oversized}" } if dropped_oversized.positive?
        end

        def send_payload_batch(events)
          response = @transport.send_flag_evaluations(
            {
              "context" => @service_context,
              "flagEvaluations" => events,
            }
          )
          if response.respond_to?(:ok?) && !response.ok?
            @logger.debug { "OpenFeature EVP: transport response was not OK: #{response.inspect}" }
          end
          response
        end

        def encoded_event_for_payload(event, base_payload_size)
          event_hash, event_size = encoded_event(event)
          return [event_hash, event_size, false] if event_fits_payload?(event_size, base_payload_size)

          degraded = degrade_event_for_payload_limit(event)
          return unless degraded

          degraded_hash, degraded_size = encoded_event(degraded)
          [degraded_hash, degraded_size, true] if event_fits_payload?(degraded_size, base_payload_size)
        end

        def encoded_event(event)
          [event, Core::Encoding::JSONEncoder.encode(event).bytesize]
        end

        def event_fits_payload?(event_size, base_payload_size)
          base_payload_size + event_size <= self.class::PAYLOAD_SIZE_LIMIT_BYTES
        end

        def degrade_event_for_payload_limit(event)
          return unless event.key?("targeting_key") || event.key?("context")

          degraded = event.dup
          degraded.delete("targeting_key")
          degraded.delete("context")
          degraded
        end

        def event_count(event)
          count = event["evaluation_count"].to_i
          count.positive? ? count : 1
        end

        def record_telemetry_count(metric_name, count, reason: nil)
          return unless count.positive?

          tags = reason ? {reason: reason} : {}
          @telemetry&.inc(TELEMETRY_NAMESPACE, metric_name, count, tags: tags)
        rescue => e
          @logger.debug { "OpenFeature EVP: telemetry error: #{e.class}: #{e.message}" }
        end
      end
    end
  end
end
