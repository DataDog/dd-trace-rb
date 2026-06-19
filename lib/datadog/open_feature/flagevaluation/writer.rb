# frozen_string_literal: true

require_relative 'aggregator'
require_relative '../../core/utils/time'

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
        FLUSH_INTERVAL_SECONDS = 10
        DRAIN_INTERVAL_SECONDS = 0.1
        QUEUE_SIZE = 4_096

        # Service context fields for the batch wrapper.
        attr_reader :service_context

        # Observable count of events dropped because the async hand-off queue was full.
        # Reset to 0 each flush after being emitted, mirroring the aggregator's overflow counter.
        attr_reader :dropped_queue_overflow

        def initialize(transport:, logger:)
          @transport = transport
          @logger = logger
          @aggregator = Aggregator.new
          @queue = SizedQueue.new(QUEUE_SIZE)
          @stop_mutex = Mutex.new
          @stop_cond = ConditionVariable.new
          @stopped = false
          @dropped_queue_overflow = 0

          @service_context = build_service_context
          @thread = start_background_thread
        end

        # Non-blocking enqueue from the finally hook. Drops + counts on overflow.
        # Context is flattened/pruned before the bounded queue so queued snapshots stay bounded.
        def enqueue(**event)
          bounded_event = {
            flag_key: event[:flag_key],
            variant: event[:variant],
            allocation_key: event[:allocation_key],
            error_message: event[:error_message],
            targeting_key: event[:targeting_key],
            eval_time_ms: event[:eval_time_ms],
            attrs: Aggregator.prune_context(event[:attrs] || {}),
          }
          @queue.push(bounded_event, true)
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
          @thread&.join(5)
        end

        private

        def build_service_context
          config = Datadog.configuration
          ctx = {'service' => config.service.to_s}
          ctx['env'] = config.env if config.env && !config.env.empty?
          ctx['version'] = config.version if config.version && !config.version.empty?
          ctx
        end

        def start_background_thread
          Thread.new do
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
          drain_queue
          flush_once
        end

        def drain_queue
          # Drain async queue into aggregator (background thread only)
          until @queue.empty?
            begin
              event = @queue.pop(true)
              # event is the untyped keyword hash pushed by #enqueue; its required keys
              # cannot be statically verified after the SizedQueue round-trip.
              @aggregator.record(**event) # steep:ignore
            rescue ThreadError
              break
            end
          end
        end

        def flush_once
          snapshot = @aggregator.flush_and_reset
          dropped_overflow = snapshot[:dropped_degraded_overflow].to_i
          dropped_queue = take_dropped_queue_overflow

          emit_drop_counts(dropped_queue, dropped_overflow)

          events = build_events(snapshot)
          return if events.empty?

          payload = {
            'context' => @service_context,
            'flagEvaluations' => events,
          }

          @transport.send_flag_evaluations(payload)
        rescue => e
          @logger.debug { "OpenFeature EVP: flush error: #{e.class}: #{e.message}" }
        end

        # Read-and-reset the queue-overflow drop counter under the stop mutex.
        def take_dropped_queue_overflow
          @stop_mutex.synchronize do
            n = @dropped_queue_overflow
            @dropped_queue_overflow = 0
            n
          end
        end

        # Emit (log) the observable drop counts so backpressure is never silently lost.
        # Σ(emitted tier counts + these drops) == evaluations processed.
        def emit_drop_counts(dropped_queue, dropped_overflow)
          return if dropped_queue.zero? && dropped_overflow.zero?

          @logger.debug do
            'OpenFeature EVP: dropped events ' \
              "queue_overflow=#{dropped_queue} degraded_overflow=#{dropped_overflow}"
          end
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
            'timestamp' => flush_time_ms,
            'flag' => {'key' => flag_key},
            'first_evaluation' => entry[:first_evaluation],
            'last_evaluation' => entry[:last_evaluation],
            'evaluation_count' => entry[:count],
          }

          event['runtime_default_used'] = true if entry[:runtime_default]
          event['error'] = {'message' => entry[:error_message]} if entry[:error_message] && !entry[:error_message].empty?

          # variant + allocation are present in both tiers (omitempty per schema).
          event['variant'] = {'key' => variant} if variant && !variant.empty?
          event['allocation'] = {'key' => allocation_key} if allocation_key && !allocation_key.empty?

          # Full-tier additionally carries targeting_key + the pruned evaluation context;
          # the degraded tier omits both.
          if tier == :full
            event['targeting_key'] = targeting_key if targeting_key && !targeting_key.empty?

            if entry[:context_attrs] && !entry[:context_attrs].empty?
              event['context'] = {'evaluation' => entry[:context_attrs]}
            end
          end

          event
        end
      end
    end
  end
end
