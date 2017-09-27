require 'time'

require 'ddtrace/buffer'

module Datadog
  module Workers
    # Asynchronous worker that executes a +Send()+ operation after given
    # seconds. Under the hood, it uses +Concurrent::TimerTask+ so that the thread
    # will perform a task at regular intervals. The thread can be stopped
    # with the +stop()+ method and can start with the +start()+ method.
    class AsyncTransport
      DEFAULT_TIMEOUT = 5

      attr_reader :trace_buffer, :service_buffer, :shutting_down

      def initialize(transport, buff_size, trace_task, service_task, interval)
        @trace_task = trace_task
        @service_task = service_task
        @flush_interval = interval
        @trace_buffer = TraceBuffer.new(buff_size)
        @service_buffer = TraceBuffer.new(buff_size)
        @transport = transport
        @shutting_down = false

        @worker = nil
        @run = false
      end

      # Callback function that process traces and executes the +send_traces()+ method.
      def callback_traces
        return if @trace_buffer.empty?

        begin
          traces = @trace_buffer.pop()
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
        return if @service_buffer.empty?

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
        return if @run
        @run = true
        @worker = Thread.new() do
          Datadog::Tracer.log.debug("Starting thread in the process: #{Process.pid}")

          while @run
            callback_traces
            callback_services
            sleep(@flush_interval) if @run
          end
        end
      end

      # Stop the timer execution. Tasks already in the queue will be executed.
      def stop
        @run = false
      end

      # Closes all available queues and waits for the trace and service buffer to flush
      def shutdown!
        return if @shutting_down || (@trace_buffer.empty? && @service_buffer.empty?)
        @shutting_down = true
        @trace_buffer.close
        @service_buffer.close
        sleep(0.1)
        timeout_time = Time.now + DEFAULT_TIMEOUT
        while (!@trace_buffer.empty? || !@service_buffer.empty?) && Time.now <= timeout_time
          sleep(0.05)
          Datadog::Tracer.log.debug('Waiting for the buffers to clear before exiting')
        end
        stop
        join
        @shutting_down = false
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
    end
  end
end
