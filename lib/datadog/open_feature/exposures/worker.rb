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

        GRACEFUL_SHUTDOWN_TIMEOUT_SECONDS = 3

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
          return false unless enabled?

          start if forked?
          buffer.push(event)
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
          buffer.close
          stop(true, GRACEFUL_SHUTDOWN_TIMEOUT_SECONDS)
        ensure
          self.enabled = false
        end

        def work_pending?
          !buffer.empty?
        end

        protected

        def after_fork
          self.buffer = Buffer.new(@buffer_limit)
        end

        private

        def send_events(events, dropped)
          return if events.empty?

          if dropped.positive?
            @logger.debug { "OpenFeature: Resolution details worker dropped #{dropped} event(s) due to full buffer" }
          end

          payload = @batch_builder.payload_for(events)
          response = @transport.send_exposures(payload)

          unless response&.ok?
            @logger.debug { "OpenFeature: Resolution details upload response was not OK: #{response.inspect}" }
          end

          response
        rescue => e
          @logger.debug { "OpenFeature: Failed to flush resolution details events: #{e.class}: #{e.message}" }
          @telemetry.report(e, description: "OpenFeature: Failed to flush resolution details events")

          nil
        end
      end
    end
  end
end
