# frozen_string_literal: true

require_relative '../../core/worker'
require_relative '../../core/workers/async'
require_relative '../../core/workers/polling'
require_relative '../../core/workers/queue'

require_relative '../buffer'
require_relative '../pipeline'
require_relative '../event'

require_relative '../transport/http'

module Datadog
  module Tracing
    module Workers
      # Writes traces to transport synchronously
      class TraceWriter < Core::Worker
        # Default maximum retry queue size for 429 responses
        DEFAULT_MAX_RETRY_QUEUE_SIZE = 100
        # Default initial backoff delay in seconds
        DEFAULT_INITIAL_BACKOFF = 1.0
        # Default maximum backoff delay in seconds
        DEFAULT_MAX_BACKOFF = 30.0
        # Backoff multiplier for exponential backoff
        BACKOFF_MULTIPLIER = 2.0

        attr_reader \
          :logger,
          :transport,
          :agent_settings

        # rubocop:disable Lint/MissingSuper
        def initialize(options = {})
          @logger = options[:logger] || Datadog.logger

          transport_options = options.fetch(:transport_options, {})
          @agent_settings = options[:agent_settings]

          @transport = options.fetch(:transport) do
            Datadog::Tracing::Transport::HTTP.default(agent_settings: agent_settings, logger: logger, **transport_options)
          end

          # Retry queue for 429 responses
          @retry_queue = []
          @retry_queue_mutex = Mutex.new
          @max_retry_queue_size = options.fetch(:max_retry_queue_size, DEFAULT_MAX_RETRY_QUEUE_SIZE)
          
          # Backoff tracking
          @current_backoff = DEFAULT_INITIAL_BACKOFF
          @initial_backoff = options.fetch(:initial_backoff, DEFAULT_INITIAL_BACKOFF)
          @max_backoff = options.fetch(:max_backoff, DEFAULT_MAX_BACKOFF)
          @last_429_time = nil
        end
        # rubocop:enable Lint/MissingSuper

        def perform(traces)
          write_traces(traces)
        end

        def write(trace)
          write_traces([trace])
        end

        def write_traces(traces)
          # First, try to flush any queued retries if we're not in a backoff period
          flush_retries if should_flush_retries?

          traces = process_traces(traces)
          responses = flush_traces(traces)
          
          # Check if any response was a 429 (too many requests)
          handle_responses(responses, traces)
          
          # Return responses for compatibility with AsyncTraceWriter
          responses
        rescue => e
          logger.warn(
            "Error while writing traces: dropped #{traces.length} items. Cause: #{e} Location: #{Array(e.backtrace).first}"
          )
          nil
        end

        def process_traces(traces)
          # Run traces through the processing pipeline
          Pipeline.process!(traces)
        end

        def flush_traces(traces)
          transport.send_traces(traces).tap do |responses|
            flush_completed.publish(responses)
          end
        end

        # TODO: Register `Datadog::Tracing::Diagnostics::EnvironmentLogger.collect_and_log!`
        # TODO: as a flush_completed subscriber when the `TraceWriter`
        # TODO: instantiation code is implemented.
        def flush_completed
          @flush_completed ||= FlushCompleted.new
        end

        # Flush completed event for worker
        class FlushCompleted < Event
          def initialize
            super(:flush_completed)
          end
        end

        private

        def handle_responses(responses, traces)
          # Check if any response is a 429
          has_429 = responses.any? { |r| r.respond_to?(:too_many_requests?) && r.too_many_requests? }
          
          if has_429
            # Queue traces for retry
            queue_for_retry(traces)
            # Update backoff
            update_backoff_on_429
          else
            # Reset backoff on success
            reset_backoff if responses.all?(&:ok?)
          end
        end

        def should_flush_retries?
          return false if @retry_queue.empty?
          return true if @last_429_time.nil?

          # Check if enough time has passed since last 429
          Time.now - @last_429_time >= @current_backoff
        end

        def flush_retries
          @retry_queue_mutex.synchronize do
            return if @retry_queue.empty?

            traces_to_retry = @retry_queue.shift
            return if traces_to_retry.nil?

            logger.debug { "Retrying #{traces_to_retry.length} traces after backoff" }

            begin
              responses = transport.send_traces(traces_to_retry)
              flush_completed.publish(responses)

              # If we got another 429, put back in queue
              has_429 = responses.any? { |r| r.respond_to?(:too_many_requests?) && r.too_many_requests? }
              
              if has_429
                queue_for_retry(traces_to_retry)
                update_backoff_on_429
              else
                # Success! Reset backoff
                reset_backoff if responses.all?(&:ok?)
              end
            rescue => e
              logger.warn(
                "Error retrying traces: dropped #{traces_to_retry.length} items. Cause: #{e}"
              )
            end
          end
        end

        def queue_for_retry(traces)
          @retry_queue_mutex.synchronize do
            if @retry_queue.length >= @max_retry_queue_size
              logger.warn(
                "Retry queue full (size: #{@retry_queue.length}), dropping #{traces.length} traces"
              )
              return
            end

            @retry_queue << traces
            logger.debug do
              "Queued #{traces.length} traces for retry due to 429 response. " \
                "Queue size: #{@retry_queue.length}"
            end
          end
        end

        def update_backoff_on_429
          @last_429_time = Time.now
          @current_backoff = [@current_backoff * BACKOFF_MULTIPLIER, @max_backoff].min
          logger.debug { "Agent backpressure detected (429). Backoff increased to #{@current_backoff}s" }
        end

        def reset_backoff
          @current_backoff = @initial_backoff
          @last_429_time = nil
          logger.debug { 'Backoff reset after successful flush' }
        end
      end

      # Writes traces to transport asynchronously,
      # using a thread & buffer.
      class AsyncTraceWriter < TraceWriter
        include Core::Workers::Queue
        include Core::Workers::Polling

        DEFAULT_BUFFER_MAX_SIZE = 1000
        FORK_POLICY_ASYNC = :async
        FORK_POLICY_SYNC = :sync

        attr_writer \
          :async

        def initialize(options = {})
          # Workers::TraceWriter settings
          super

          # Workers::Polling settings
          self.enabled = options.fetch(:enabled, true)

          # Workers::Async::Thread settings
          @async = true
          self.fork_policy = options.fetch(:fork_policy, FORK_POLICY_ASYNC)

          # Workers::IntervalLoop settings
          self.loop_base_interval = options[:interval] if options.key?(:interval)
          self.loop_back_off_ratio = options[:back_off_ratio] if options.key?(:back_off_ratio)
          self.loop_back_off_max = options[:back_off_max] if options.key?(:back_off_max)

          # Workers::Queue settings
          @buffer_size = options.fetch(:buffer_size, DEFAULT_BUFFER_MAX_SIZE)
          self.buffer = TraceBuffer.new(@buffer_size)

          @shutdown_timeout = options.fetch(:shutdown_timeout, Core::Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT)
        end

        # NOTE: #perform is wrapped by other modules:
        #       Polling --> Async --> IntervalLoop --> AsyncTraceWriter --> TraceWriter
        #
        # WARNING: This method breaks the Liskov Substitution Principle -- TraceWriter#perform is spec'd to return the
        # result from the writer, whereas this method always returns nil.
        def perform(traces)
          super.tap do |responses|
            loop_back_off! if responses.find(&:server_error?)
          end

          nil
        end

        def stop(force_stop = false, timeout = @shutdown_timeout)
          buffer.close if running?
          super
        end

        def enqueue(trace)
          buffer.push(trace)
        end

        def dequeue
          # Wrap results in Array because they are
          # splatted as args against TraceWriter#perform.
          [buffer.pop]
        end

        # Are there more traces to be processed next?
        def work_pending?
          !buffer.empty?
        end

        def async?
          @async == true
        end

        def fork_policy=(policy)
          # Translate to Workers::Async::Thread policy
          thread_fork_policy = case policy
          when Core::Workers::Async::Thread::FORK_POLICY_STOP
            policy
          when FORK_POLICY_SYNC
            # Stop the async thread because the writer
            # will bypass and run synchronously.
            Core::Workers::Async::Thread::FORK_POLICY_STOP
          else
            Core::Workers::Async::Thread::FORK_POLICY_RESTART
          end

          # Update thread fork policy
          super(thread_fork_policy)

          # Update local policy
          @writer_fork_policy = policy
        end

        def after_fork
          # In multiprocess environments, forks will share the same buffer until its written to.
          # A.K.A. copy-on-write. We don't want forks to write traces generated from another process.
          # Instead, we reset it after the fork. (Make sure any enqueue operations happen after this.)
          self.buffer = TraceBuffer.new(@buffer_size)

          # Switch to synchronous mode if configured to do so.
          # In some cases synchronous writing is preferred because the fork will be short lived.
          @async = false if @writer_fork_policy == FORK_POLICY_SYNC
        end

        # WARNING: This method breaks the Liskov Substitution Principle -- TraceWriter#write is spec'd to return the
        # result from the writer, whereas this method returns something else when running in async mode.
        def write(trace)
          # Start worker thread. If the process has forked, it will trigger #after_fork to
          # reconfigure the worker accordingly.
          # NOTE: It's important we do this before queuing or it will drop the current trace,
          #       because #after_fork resets the buffer.
          perform

          # Queue the trace if running asynchronously, otherwise short-circuit and write it directly.
          async? ? enqueue(trace) : write_traces([trace])
        end
      end
    end
  end
end
