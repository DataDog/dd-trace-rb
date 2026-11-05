# frozen_string_literal: true

require_relative "../../core/utils/time"
require_relative "../../core/workers/queue"
require_relative "../../core/workers/polling"

require_relative "buffer"
require_relative "batch_builder"

module Datadog
  module OpenFeature
    module Exposures
      # This class is responsible for sending exposures to the Agent
      class Worker
        include Core::Workers::Queue
        include Core::Workers::Polling

        GRACEFUL_SHUTDOWN_EXTRA_SECONDS = 5
        GRACEFUL_SHUTDOWN_WAIT_INTERVAL_SECONDS = 0.5

        DEFAULT_FLUSH_INTERVAL_SECONDS = 30
        DEFAULT_BUFFER_LIMIT = Buffer::DEFAULT_LIMIT

        def initialize(
          settings:,
          transport:,
          telemetry:,
          logger:,
          flush_interval_seconds: DEFAULT_FLUSH_INTERVAL_SECONDS,
          buffer_limit: DEFAULT_BUFFER_LIMIT
        )
          @logger = logger
          @transport = transport
          @telemetry = telemetry
          @batch_builder = BatchBuilder.new(settings)
          @buffer_limit = buffer_limit

          self.buffer = Buffer.new(buffer_limit)
          self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_RESTART
          self.loop_base_interval = flush_interval_seconds
          self.enabled = true
        end

        def start
          return if !enabled? || running?

          perform
        end

        def stop(force_stop = false, timeout = Core::Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT)
          buffer.close if running?

          super
        end

        def enqueue(event)
          unless buffer.push(event)
            @logger.debug { "Feature Flags: exposure not queued: buffer closed" }
            return false
          end

          start unless running?

          true
        end

        def dequeue
          [buffer.pop, buffer.dropped_count]
        end

        def perform(*args)
          events, dropped = args
          send_events(Array(events), dropped.to_i)
        end

        def graceful_shutdown
          return false unless enabled? || !run_loop?

          self.enabled = false

          started = Core::Utils::Time.get_time
          wait_time = loop_base_interval + GRACEFUL_SHUTDOWN_EXTRA_SECONDS

          loop do
            break if buffer.empty? && !in_iteration?

            sleep(GRACEFUL_SHUTDOWN_WAIT_INTERVAL_SECONDS)
            break if Core::Utils::Time.get_time - started > wait_time
          end

          log_shutdown_outcome(wait_time)
          stopped = stop(true)
          @logger.debug("Feature Flags: exposure worker stopped") unless running?
          stopped
        end

        private

        def send_events(events, dropped)
          return if events.empty?

          if dropped.positive?
            @logger.debug do
              "Feature Flags: dropped #{dropped} older queued exposure event(s) because the exposure buffer was full"
            end
          end

          payload = @batch_builder.payload_for(events)
          @logger.debug { "Feature Flags: flushing #{events.size} exposure event(s) to the Datadog Agent" }
          response = @transport.send_exposures(payload)

          if response&.ok?
            @logger.debug { "Feature Flags: sent #{events.size} exposure event(s) to the Datadog Agent" }
          else
            @logger.debug do
              "Feature Flags: exposure upload response was not OK; dropping #{events.size} exposure event(s) " \
                "without retry: #{response.inspect}"
            end
          end

          response
        rescue => e
          @logger.debug do
            "Feature Flags: failed to flush exposure events; dropping #{events.size} exposure event(s) " \
              "without retry: #{e.class}: #{e.message}"
          end
          @telemetry.report(e, description: "OpenFeature: Failed to flush resolution details events")

          nil
        end

        def log_shutdown_outcome(wait_time)
          @logger.debug do
            queued = buffer.length
            evicted = buffer.pending_dropped_count
            uploading = !!in_iteration?
            remaining = queued.positive? ? "; #{queued} queued exposure event(s) will not be sent" : "; no queued exposure events remain"
            remaining += "; #{evicted} exposure event(s) evicted from the full buffer were not sent" if evicted.positive?
            outcome = uploading ? "; the in-flight upload may still report sent or dropping during shutdown; if forcibly terminated, its outcome will not be reported" : ""
            "Feature Flags: exposure shutdown wait finished; queued=#{queued}, " \
              "upload_in_progress=#{uploading}, wait_budget=#{wait_time}s#{remaining}#{outcome}"
          end
        end
      end
    end
  end
end
