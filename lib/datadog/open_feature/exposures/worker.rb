# frozen_string_literal: true

require 'thread'

require_relative 'batch'
require_relative 'buffer'
require_relative 'context'

module Datadog
  module OpenFeature
    module Exposures
      class Worker
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
          @flush_interval_seconds = flush_interval_seconds
          @buffer = Buffer.new(limit: buffer_limit)
          @context_builder = context_builder || -> { Context.build }

          @state_mutex = Mutex.new
          @signal = ConditionVariable.new
          @thread = nil
          @running = false
          @stopped = false

          @flush_mutex = Mutex.new
        end

        def enqueue(event)
          return false if stopped?

          start_worker

          @buffer.push(event)

          wakeup_worker if @buffer.full?
          true
        end

        def flush
          events, dropped = @buffer.drain
          log_drops(dropped) if dropped.positive?

          return if events.empty?

          payload = build_payload(events)
          send_payload(payload)
        end

        def stop
          thread = nil

          @state_mutex.synchronize do
            thread = @thread
            return unless thread

            @stopped = true
            @signal.broadcast
          end

          thread.join if thread.alive?
          flush
        end

        private

        def start_worker
          @state_mutex.synchronize do
            return if @running || @stopped

            @thread = ::Thread.new { worker_loop }
            @thread.name = self.class.name
            @running = true
          end
        end

        def worker_loop
          loop do
            break if wait_for_signal_or_timeout

            flush
          end
        rescue => e
          logger.debug { "Exposure worker loop error: #{e.class}: #{e.message}" }
        ensure
          flush

          @state_mutex.synchronize do
            @running = false
            @thread = nil
          end
        end

        def wait_for_signal_or_timeout
          @state_mutex.synchronize do
            return true if @stopped

            @signal.wait(@state_mutex, @flush_interval_seconds)

            @stopped
          end
        end

        def wakeup_worker
          @state_mutex.synchronize do
            return if @thread.nil? || @stopped

            @signal.broadcast
          end
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

        def stopped?
          @state_mutex.synchronize { @stopped }
        end
      end
    end
  end
end
