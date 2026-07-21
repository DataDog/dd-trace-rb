# frozen_string_literal: true

require_relative "aggregator"
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

        REASON_QUEUE_OVERFLOW = "queue_overflow"
        REASON_DEGRADED_CAP = "degraded_cap"
        REASON_CARDINALITY_CAP = "cardinality_cap"
        REASON_PAYLOAD_LIMIT = "payload_limit"

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

          self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_RESTART

          @service_context = build_service_context
          start_background_thread
        end

        # Non-blocking enqueue from the finally hook. Drops + counts on overflow.
        # Context flattening/pruning runs in the background writer, not on the caller eval thread.
        def enqueue(**event)
          start_background_thread if forked?

          attrs = event[:attrs]
          attrs = attrs.is_a?(Hash) ? snapshot_context_value(attrs, {}, 0) || {} : {}
          bounded_event = {
            flag_key: event[:flag_key],
            variant: event[:variant],
            allocation_key: event[:allocation_key],
            error_message: event[:error_message],
            runtime_default: event[:runtime_default],
            targeting_key: event[:targeting_key],
            eval_time_ms: event[:eval_time_ms],
            attrs: attrs,
          }
          @queue.push(bounded_event, true)
          start_background_thread unless running?
        rescue ThreadError
          # Queue full — drop and count (best-effort, same as Go: drop-and-count). The count is
          # emitted on the next flush so backpressure is observable, not silently lost.
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
        end

        private

        def build_service_context
          config = Datadog.configuration
          ctx = {"service" => config.service.to_s}
          ctx["env"] = config.env if config.env && !config.env.empty?
          ctx["version"] = config.version if config.version && !config.version.empty?
          ctx
        end

        def snapshot_context_value(value, seen, depth)
          return if depth > Aggregator::MAX_CONTEXT_DEPTH

          case value
          when Hash
            object_id = value.object_id
            return if seen[object_id]

            seen[object_id] = true
            value.each_with_object({}) do |(key, child_value), snapshot|
              snapshot[key.is_a?(String) ? key.dup : key] = snapshot_context_value(child_value, seen, depth + 1)
            end.tap { seen.delete(object_id) }
          when Array
            object_id = value.object_id
            return if seen[object_id]

            seen[object_id] = true
            value.map { |child_value| snapshot_context_value(child_value, seen, depth + 1) }.tap { seen.delete(object_id) }
          when String
            value.dup
          else
            begin
              value.dup
            rescue TypeError
              value
            end
          end
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
            return if @stopped

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
                attrs: event[:attrs].is_a?(Hash) ? event[:attrs] : {},
                error_message: event[:error_message],
                runtime_default: event[:runtime_default],
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
          dropped_queue = take_dropped_queue_overflow

          emit_drop_counts(dropped_queue, dropped_overflow)

          events = build_events(snapshot)
          emit_degraded_counts(snapshot[:degraded].values.sum { |entry| entry[:count].to_i })
          return if events.empty?

          send_payload_batches(events)
        rescue => e
          @logger.debug { "OpenFeature EVP: flush error: #{e.class}: #{e.message}" }
        end

        # Read-and-reset the queue-overflow drop counter under the stop mutex.
        def take_dropped_queue_overflow
          @stop_mutex.synchronize do
            count = @dropped_queue_overflow
            @dropped_queue_overflow = 0
            count
          end
        end

        # Emit (log) the observable drop counts so backpressure is never silently lost.
        # Σ(emitted tier counts + these drops) == evaluations processed.
        def emit_drop_counts(dropped_queue, dropped_overflow)
          return if dropped_queue.zero? && dropped_overflow.zero?

          record_telemetry_count(ROWS_DROPPED_METRIC, dropped_queue, reason: REASON_QUEUE_OVERFLOW)
          record_telemetry_count(ROWS_DROPPED_METRIC, dropped_overflow, reason: REASON_DEGRADED_CAP)

          @logger.debug do
            "OpenFeature EVP: dropped events " \
              "queue_overflow=#{dropped_queue} degraded_overflow=#{dropped_overflow}"
          end
        end

        def emit_degraded_counts(degraded_count)
          record_telemetry_count(ROWS_DEGRADED_METRIC, degraded_count, reason: REASON_CARDINALITY_CAP)
        end

        # Build flagEvaluationEvent list from aggregation snapshot.
        # Full-tier entries include all optional fields; degraded entries omit targeting_key + context.
        def build_events(snapshot)
          flush_time_ms = (Core::Utils::Time.now.to_f * 1000).to_i
          events = []

          snapshot[:full].each do |key, entry|
            flag_key, variant, allocation_key, _runtime_default, _error_message, targeting_key, _ctx_key = key
            event = build_event(
              flag_key: flag_key, variant: variant, allocation_key: allocation_key,
              targeting_key: targeting_key, entry: entry, flush_time_ms: flush_time_ms, tier: :full,
            )
            events << event
          end

          snapshot[:degraded].each do |key, entry|
            flag_key, variant, allocation_key, _runtime_default, _error_message = key
            event = build_event(
              flag_key: flag_key, variant: variant, allocation_key: allocation_key,
              targeting_key: nil, entry: entry, flush_time_ms: flush_time_ms, tier: :degraded,
            )
            events << event
          end

          events
        end

        def build_event(flag_key:, variant:, allocation_key:, targeting_key:, entry:, flush_time_ms:, tier:)
          # @type var event: ::Hash[::String, untyped]
          event = {
            "timestamp" => flush_time_ms,
            "flag" => {"key" => flag_key},
            "first_evaluation" => entry[:first_evaluation],
            "last_evaluation" => entry[:last_evaluation],
            "evaluation_count" => entry[:count],
          }

          event["runtime_default_used"] = true if entry[:runtime_default]
          event["error"] = {"message" => entry[:error_message]} if entry[:error_message] && !entry[:error_message].empty?

          # variant + allocation are present in both tiers (omitempty per schema).
          event["variant"] = {"key" => variant} if variant && !variant.empty?
          event["allocation"] = {"key" => allocation_key} if allocation_key && !allocation_key.empty?

          # Full-tier additionally carries targeting_key + the pruned evaluation context;
          # the degraded tier omits both.
          if tier == :full
            event["targeting_key"] = targeting_key if targeting_key && !targeting_key.empty?

            if entry[:context_attrs] && !entry[:context_attrs].empty?
              event["context"] = {"evaluation" => entry[:context_attrs]}
            end
          end

          event
        end

        def send_payload_batches(events)
          context_json = Core::Encoding::JSONEncoder.encode(@service_context)
          payload_prefix = "{\"context\":#{context_json},\"flagEvaluations\":["
          payload_suffix = "]}"
          base_payload_size = payload_prefix.bytesize + payload_suffix.bytesize

          batch = []
          batch_size = base_payload_size
          dropped_oversized = 0
          payload_limit_degraded = 0
          payload_splits = 0

          events.each do |event|
            encoded_event = encoded_event_for_payload(event, base_payload_size)
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
          record_telemetry_count(PAYLOAD_SPLITS_METRIC, payload_splits)
          emit_payload_oversize_drops(dropped_oversized) if dropped_oversized.positive?
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

        def emit_payload_oversize_drops(dropped_oversized)
          @logger.debug { "OpenFeature EVP: dropped events payload_oversize=#{dropped_oversized}" }
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
