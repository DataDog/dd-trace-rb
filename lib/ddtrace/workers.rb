require 'time'

require 'ddtrace/buffer'
require 'ddtrace/runtime/metrics'

module Datadog
  module Workers
    # Asynchronous worker that executes a +Send()+ operation after given
    # seconds. Under the hood, it uses +Concurrent::TimerTask+ so that the thread
    # will perform a task at regular intervals. The thread can be stopped
    # with the +stop()+ method and can start with the +start()+ method.
    class AsyncTransport
      DEFAULT_TIMEOUT = 5
      BACK_OFF_RATIO = 1.2
      BACK_OFF_MAX = 5
      SHUTDOWN_TIMEOUT = 1

      attr_reader \
        :trace_buffer

      def initialize(options = {})
        @transport = options[:transport]

        # Callbacks
        @trace_task = options[:on_trace]
        @runtime_metrics_task = options[:on_runtime_metrics]

        # Intervals
        interval = options.fetch(:interval, 1)
        @flush_interval = interval
        @back_off = interval

        # Buffers
        buffer_size = options.fetch(:buffer_size, 100)
        @trace_buffer = TraceBuffer.new(buffer_size)

        # Threading
        @shutdown = ConditionVariable.new
        @mutex = Mutex.new
        @worker = nil
        @run = false
      end

      # Callback function that process traces and executes the +send_traces()+ method.
      def callback_traces
        return true if @trace_buffer.empty?

        begin
          traces = @trace_buffer.pop
          traces = Pipeline.process!(traces)
          @trace_task.call(traces, @transport) unless @trace_task.nil?
        rescue StandardError => e
          # ensures that the thread will not die because of an exception.
          # TODO[manu]: findout the reason and reschedule the send if it's not
          # a fatal exception
          Datadog::Tracer.log.error(
            "Error during traces flush: dropped #{traces.length} items. Cause: #{e} Location: #{e.backtrace.first}"
          )
        end
      end

      def callback_runtime_metrics
        @runtime_metrics_task.call unless @runtime_metrics_task.nil?
      rescue StandardError => e
        Datadog::Tracer.log.error(
          "Error during runtime metrics flush. Cause: #{e} Location: #{e.backtrace.first}"
        )
      end

      # Start the timer execution.
      def start
        @mutex.synchronize do
          return if @run
          @run = true
          Tracer.log.debug("Starting thread in the process: #{Process.pid}")
          @worker = Thread.new { perform }
        end
      end

      # Closes all available queues and waits for the trace buffer to flush
      def stop
        @mutex.synchronize do
          return unless @run

          @trace_buffer.close
          @run = false
          @shutdown.signal
        end

        join
        true
      end

      # Block until executor shutdown is complete or until timeout seconds have passed.
      def join
        @worker.join(SHUTDOWN_TIMEOUT)
      end

      # Enqueue an item in the trace internal buffer. This operation is thread-safe
      # because uses the +TraceBuffer+ data structure.
      def enqueue_trace(trace)
        @trace_buffer.push(trace)
      end

      private

      alias flush_data callback_traces

      def perform
        loop do
          @back_off = flush_data ? @flush_interval : [@back_off * BACK_OFF_RATIO, BACK_OFF_MAX].min

          callback_runtime_metrics

          @mutex.synchronize do
            return if !@run && @trace_buffer.empty?
            @shutdown.wait(@mutex, @back_off) if @run # do not wait when shutting down
          end
        end
      end
    end
  end
end
