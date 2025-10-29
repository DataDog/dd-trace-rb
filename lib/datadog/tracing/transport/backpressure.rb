# frozen_string_literal: true

require 'thread'

module Datadog
  module Tracing
    module Transport
      # Handles backpressure from the Trace Agent by implementing a retry queue
      # with exponential backoff for 429 Too Many Requests responses.
      module Backpressure
        # Configuration for backpressure retry behavior
        class Configuration
          # Maximum number of payloads to queue for retry
          DEFAULT_MAX_RETRY_QUEUE_SIZE = 100
          # Initial backoff time in seconds
          DEFAULT_INITIAL_BACKOFF_SECONDS = 1.0
          # Maximum backoff time in seconds
          DEFAULT_MAX_BACKOFF_SECONDS = 30.0
          # Backoff multiplier for exponential backoff
          DEFAULT_BACKOFF_MULTIPLIER = 2.0

          attr_accessor :max_retry_queue_size, :initial_backoff_seconds, :max_backoff_seconds, :backoff_multiplier

          def initialize(
            max_retry_queue_size: DEFAULT_MAX_RETRY_QUEUE_SIZE,
            initial_backoff_seconds: DEFAULT_INITIAL_BACKOFF_SECONDS,
            max_backoff_seconds: DEFAULT_MAX_BACKOFF_SECONDS,
            backoff_multiplier: DEFAULT_BACKOFF_MULTIPLIER
          )
            @max_retry_queue_size = max_retry_queue_size
            @initial_backoff_seconds = initial_backoff_seconds
            @max_backoff_seconds = max_backoff_seconds
            @backoff_multiplier = backoff_multiplier
          end
        end

        # Manages the retry queue and exponential backoff logic for trace payloads
        class RetryQueue
          attr_reader :config, :logger, :client

          def initialize(client:, config: Configuration.new, logger: Datadog.logger)
            @client = client
            @config = config
            @logger = logger
            @queue = Queue.new
            @mutex = Mutex.new
            @current_backoff = config.initial_backoff_seconds
            @retry_thread = nil
            @shutdown = false
          end

          # Adds a request to the retry queue if space is available
          # @param request [Request] the request to retry
          # @return [Boolean] true if queued, false if queue is full
          def enqueue(request)
            @mutex.synchronize do
              if @queue.size >= config.max_retry_queue_size
                logger.warn do
                  "Retry queue is full (size: #{@queue.size}). " \
                    "Dropping payload with #{request.parcel.trace_count} traces."
                end
                Datadog.health_metrics.queue_dropped(1) if Datadog.respond_to?(:health_metrics)
                return false
              end

              @queue.push(request)
              logger.debug { "Queued payload for retry. Queue size: #{@queue.size}" }

              # Start retry thread if not already running
              start_retry_thread unless @retry_thread&.alive?

              true
            end
          end

          # Returns the current size of the retry queue
          # @return [Integer] the number of items in the queue
          def size
            @queue.size
          end

          # Shuts down the retry queue and stops the retry thread
          def shutdown
            @shutdown = true
            if @retry_thread&.alive?
              @retry_thread.wakeup rescue nil # Wake up the thread if sleeping
              @retry_thread.join(5) # Wait up to 5 seconds for thread to finish
            end
          end

          private

          def start_retry_thread
            @retry_thread = Thread.new do
              Thread.current.name = 'dd-trace-backpressure-retry'
              retry_loop
            rescue => e
              logger.error do
                "Error in backpressure retry thread: #{e.class.name} #{e.message} " \
                  "Location: #{Array(e.backtrace).first}"
              end
            end
          end

          def retry_loop
            @current_backoff = config.initial_backoff_seconds

            until @shutdown
              # Wait for items in the queue
              if @queue.empty?
                sleep(0.1) # Small sleep to avoid busy waiting
                next
              end

              request = @queue.pop

              # Attempt to send the request
              begin
                response = client.send_traces_payload(request)

                if response.ok?
                  # Successfully sent, reset backoff
                  @current_backoff = config.initial_backoff_seconds
                  logger.debug { 'Successfully retried payload from backpressure queue' }
                elsif response.too_many_requests?
                  # Still getting 429, re-queue and backoff
                  @queue.push(request) unless @shutdown
                  apply_backoff
                else
                  # Non-retriable error (e.g., 4xx/5xx), drop the payload
                  logger.warn do
                    "Dropping payload from retry queue after non-retriable error. Response code: #{response.code}"
                  end
                end
              rescue => e
                # Exception during retry, drop the payload
                logger.warn do
                  "Dropping payload from retry queue after exception: #{e.class.name} #{e.message}"
                end
              end
            end
          end

          def apply_backoff
            sleep(@current_backoff) unless @shutdown
            @current_backoff = [@current_backoff * config.backoff_multiplier, config.max_backoff_seconds].min
            logger.debug { "Applied exponential backoff. Next backoff: #{@current_backoff}s" }
          end
        end
      end
    end
  end
end
