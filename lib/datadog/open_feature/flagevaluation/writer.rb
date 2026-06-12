# frozen_string_literal: true

require_relative 'aggregator'
require_relative '../../core/utils/time'

module Datadog
  module OpenFeature
    module FlagEvaluation
      # Background writer that drains the two-tier aggregation maps and POSTs
      # batches to /evp_proxy/v2/api/v2/flagevaluations every FLUSH_INTERVAL_SECONDS.
      #
      # The writer owns the aggregation cycle:
      #   1. Hook calls enqueue (non-blocking) — never aggregates inline.
      #   2. Background thread wakes, calls aggregator.record for each enqueued event, flushes.
      #   3. flush_once drains aggregation maps, builds payload, sends via transport.
      #
      # Thread model: MRI Ruby GIL — Mutex + SizedQueue + Thread.
      class Writer
        FLUSH_INTERVAL_SECONDS = 10
        QUEUE_SIZE = 4_096

        # Service context fields for the batch wrapper.
        attr_reader :service_context

        def initialize(transport:, logger:)
          @transport  = transport
          @logger     = logger
          @aggregator = Aggregator.new
          @queue      = SizedQueue.new(QUEUE_SIZE)
          @mutex      = Mutex.new
          @stopped    = false

          @service_context = build_service_context
          @thread = start_background_thread
        end

        # Non-blocking enqueue from the finally hook. Drops on overflow.
        def enqueue(**event)
          @queue.push(event, true)
        rescue ThreadError
          # Queue full — drop silently (best-effort, same as Go: drop-and-count)
          @logger.debug { 'OpenFeature EVP: flag eval event queue full; dropping event' }
        end

        # Stop the background thread and flush remaining events.
        def stop
          @stopped = true
          @thread&.join(5)
        end

        private

        def build_service_context
          config = Datadog.configuration
          ctx = {'service' => config.service.to_s}
          ctx['env']     = config.env     if config.env && !config.env.empty?
          ctx['version'] = config.version if config.version && !config.version.empty?
          ctx
        end

        def start_background_thread
          Thread.new do
            until @stopped
              begin
                sleep(FLUSH_INTERVAL_SECONDS)
                drain_and_flush
              rescue => e
                @logger.debug { "OpenFeature EVP: writer error: #{e.class}: #{e.message}" }
              end
            end
          end
        end

        def drain_and_flush
          # Drain async queue into aggregator (background thread only)
          until @queue.empty?
            begin
              event = @queue.pop(true)
              @aggregator.record(**event)
            rescue ThreadError
              break
            end
          end

          flush_once
        end

        def flush_once
          snapshot = @aggregator.flush_and_reset
          events   = build_events(snapshot)
          return if events.empty?

          payload = {
            'context' => @service_context,
            'flagEvaluations' => events,
          }

          @transport.send_flag_evaluations(payload)
        rescue => e
          @logger.debug { "OpenFeature EVP: flush error: #{e.class}: #{e.message}" }
        end

        # Build flagEvaluationEvent list from aggregation snapshot.
        # Full-tier entries include all optional fields; degraded entries omit targeting_key + context.
        def build_events(snapshot)
          now_ms = (Core::Utils::Time.now.to_f * 1000).to_i
          events = []

          snapshot[:full].each do |key, entry|
            flag_key, variant, allocation_key, reason, targeting_key, _ctx_key = key
            event = build_event(
              flag_key: flag_key, variant: variant, allocation_key: allocation_key,
              reason: reason, targeting_key: targeting_key, entry: entry, now_ms: now_ms, tier: :full,
            )
            events << event
          end

          snapshot[:degraded].each do |key, entry|
            flag_key, variant, allocation_key, reason = key
            event = build_event(
              flag_key: flag_key, variant: variant, allocation_key: allocation_key,
              reason: reason, targeting_key: nil, entry: entry, now_ms: now_ms, tier: :degraded,
            )
            events << event
          end

          events
        end

        def build_event(flag_key:, variant:, allocation_key:, reason:, targeting_key:, entry:, now_ms:, tier:)
          event = {
            'timestamp'        => now_ms,
            'flag'             => {'key' => flag_key},
            'first_evaluation' => entry[:first_evaluation],
            'last_evaluation'  => entry[:last_evaluation],
            'evaluation_count' => entry[:count],
          }

          event['runtime_default_used'] = true if entry[:runtime_default]

          if tier == :full
            # Full-tier: include variant, allocation, targeting_key, context (omitempty per schema)
            event['variant']       = {'key' => variant}       if variant && !variant.empty?
            event['allocation']    = {'key' => allocation_key} if allocation_key && !allocation_key.empty?
            event['targeting_key'] = targeting_key             if targeting_key && !targeting_key.empty?

            if entry[:context_attrs] && !entry[:context_attrs].empty?
              event['context'] = {'evaluation' => entry[:context_attrs]}
            end
          else
            # Degraded tier: variant + allocation only (no targeting_key, no context)
            event['variant']    = {'key' => variant}        if variant && !variant.empty?
            event['allocation'] = {'key' => allocation_key} if allocation_key && !allocation_key.empty?
          end

          event
        end
      end
    end
  end
end
