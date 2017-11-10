require 'time'
require 'concurrent'

require 'ddtrace/buffer'

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

      attr_reader :trace_buffer, :service_buffer, :shutting_down

      def initialize(transport, buff_size, trace_task, service_task, interval)
        @trace_task = trace_task
        @service_task = service_task
        @flush_interval = interval
        @trace_buffer = TraceBuffer.new(buff_size)
        @service_buffer = TraceBuffer.new(buff_size)
        @transport = transport
        @shutting_down = false
        @mutex = Mutex.new

        @worker = nil
        @run = false
      end

      # Callback function that process traces and executes the +send_traces()+ method.
      def callback_traces
        return true if @trace_buffer.empty?

        begin
          traces = @trace_buffer.pop()
          traces = Pipeline.process!(traces)
          @trace_task.call(traces, @transport)
        rescue StandardError => e
          # ensures that the thread will not die because of an exception.
          # TODO[manu]: findout the reason and reschedule the send if it's not
          # a fatal exception
          Datadog::Tracer.log.error("Error during traces flush: dropped #{items.length} items. Cause: #{e}")
        end
      end

      # Callback function that process traces and executes the +send_services()+ method.
      def callback_services
        return true if @service_buffer.empty?

        begin
          services = @service_buffer.pop()
          @service_task.call(services[0], @transport)
        rescue StandardError => e
          # ensures that the thread will not die because of an exception.
          # TODO[manu]: findout the reason and reschedule the send if it's not
          # a fatal exception
          Datadog::Tracer.log.error("Error during services flush: dropped #{items.length} items. Cause: #{e}")
        end
      end

      # Start the timer execution.
      def start
        return if run
        @mutex.synchronize { @run = true }
        @worker = Thread.new() do
          Datadog::Tracer.log.debug("Starting thread in the process: #{Process.pid}")

          # Loop first - protects against edge race condition where code in shutdown! is run faster/before
          # this method
          loop do
            start_time = nil
            # If buffer is left open, continue flushing every @flush_interval
            unless @trace_buffer.closed?
              start_time = Time.now

              while !@trace_buffer.closed? && (Time.now - start_time < @flush_interval)
                sleep(0.01)
              end
            end

            # Flush when buffer is closed or every @flush_interval
            if @trace_buffer.closed? || (Time.now - start_time >= @flush_interval)
              trace_call = Concurrent::Promise.new { callback_traces }.execute
              callback_services

              # Increase @flush_interval if callback_traces returns immediately with nil
              if trace_call.state == :fulfilled && trace_call.value.nil?
                @flush_interval = [@flush_interval * BACK_OFF_RATIO, BACK_OFF_MAX].min

              # Block on callback_traces if buffer is closed
              elsif @trace_buffer.closed? && trace_call.state == :pending
                trace_call.wait(DEFAULT_TIMEOUT)
              end
            end

            break unless run
          end
        end
      end

      # Stop the timer execution. Tasks already in the queue will be executed.
      def stop
        @mutex.synchronize { @run = false }
      end

      # Closes all available queues and waits for the trace and service buffer to flush
      def shutdown!
        return false if @shutting_down
        @shutting_down = true
        @trace_buffer.close
        @service_buffer.close
        stop
        join
        @shutting_down = false
        true
      end

      # Block until executor shutdown is complete or until timeout seconds have passed.
      def join
        @worker.join(5)
      end

      # Enqueue an item in the trace internal buffer. This operation is thread-safe
      # because uses the +TraceBuffer+ data structure.
      def enqueue_trace(trace)
        @trace_buffer.push(trace)
      end

      # Enqueue an item in the service internal buffer. This operation is thread-safe.
      def enqueue_service(service)
        return if service == {} # no use to send this, not worth it
        @service_buffer.push(service)
      end

      private

      def run
        @mutex.synchronize { @run }
      end
    end
  end
end
