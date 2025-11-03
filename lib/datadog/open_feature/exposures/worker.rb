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

        def initialize(
          transport:,
          logger: Datadog.logger,
          flush_interval_seconds: DEFAULT_FLUSH_INTERVAL_SECONDS,
          buffer_limit: DEFAULT_BUFFER_LIMIT,
          context_builder: nil
        )
          @transport = transport
          @logger = logger
          @context_builder = context_builder || -> { Context.build }
          @buffer_limit = buffer_limit
          self.buffer = Buffer.new(buffer_limit)
          @flush_mutex = Mutex.new

          self.loop_base_interval = flush_interval_seconds
          self.enabled = true
        end

        def start
          return if !enabled? || running? || forked?

          perform
        end

        def enqueue(event)
          return false if forked?

          buffer.push(event)

          flush if buffer_length >= @buffer_limit

          start unless running?

          true
        end

        def flush
          process(*buffer.pop)
        end

        def stop(force_stop = false, timeout = Datadog::Core::Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT)
          result = super(force_stop, timeout)
          flush
          result
        end

        private

        def perform(events = nil, dropped = 0)
          process(events || [], dropped)
        end

        def buffer_length
          buffer.length
        end

        def dequeue
          buffer.pop
        end

        def process(events, dropped)
          log_drops(dropped) if dropped.positive?

          return if events.nil? || events.empty?

          payload = build_payload(events)
          send_payload(payload)
        end

        def build_payload(events)
          Batch.new(context: @context_builder.call, exposures: events).to_h
        end

        def send_payload(payload)
          @flush_mutex.synchronize do
            response = @transport.send_exposures(payload)

            unless response.respond_to?(:ok?) && response.ok?
              logger.debug { "Exposure flush response: #{response.inspect}" }
            end

            response
          end
        rescue => e
          logger.debug { "Failed to flush exposure events: #{e.class}: #{e.message}" }
          nil
        end

        def log_drops(count)
          logger.debug { "Exposure worker dropped #{count} events due to full buffer" }
        end
      end
    end
  end
end
