# frozen_string_literal: true

require_relative '../../core/workers/polling'

require_relative 'batch'
require_relative 'buffer'
require_relative 'context'

module Datadog
  module OpenFeature
    module Exposures
      class Worker
        include Datadog::Core::Workers::Queue
        include Datadog::Core::Workers::Polling

        DEFAULT_FLUSH_INTERVAL_SECONDS = 30
        DEFAULT_BUFFER_LIMIT = Buffer::DEFAULT_LIMIT

        attr_reader :logger

        # NOTE: Context builder and the data model is not finished
        def initialize(
          transport:,
          logger: Datadog.logger,
          flush_interval_seconds: DEFAULT_FLUSH_INTERVAL_SECONDS,
          buffer_limit: DEFAULT_BUFFER_LIMIT,
          context_builder: nil
        )
          @logger = logger
          @transport = transport
          @context_builder = context_builder || -> { Context.build }
          @buffer_limit = buffer_limit
          @flush_mutex = Mutex.new

          self.buffer = Buffer.new(buffer_limit)
          self.loop_base_interval = flush_interval_seconds
          self.enabled = true
        end

        def start
          return if !enabled? || running? || forked?

          perform
        end

        def stop(force_stop = false, timeout = Core::Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT)
          result = super(force_stop, timeout)
          flush

          result
        end

        def enqueue(event)
          return false if forked?

          buffer.push(event)

          flush if buffer.length >= @buffer_limit
          start unless running?

          true
        end

        def dequeue
          buffer.pop
        end

        def flush
          send_events(*dequeue)
        end

        def perform(*args)
          send_events(*args)
        end

        private

        def send_events(events, dropped = 0)
          events ||= []

          if dropped.positive?
            logger.debug do
              "OpenFeature: Exposure worker dropped #{dropped} event(s) due to full buffer"
            end
          end

          return if events.empty?

          payload = Batch.new(context: @context_builder.call, exposures: events).to_h
          send_payload(payload)
        end

        def send_payload(payload)
          @flush_mutex.synchronize do
            response = @transport.send_exposures(payload)
            logger.debug { "OpenFeature: Send exposures response was not OK: #{response.inspect}" } unless response&.ok?

            response
          end
        rescue => e
          logger.debug { "OpenFeature: Failed to flush exposure events: #{e.class}: #{e.message}" }
          nil
        end
      end
    end
  end
end
