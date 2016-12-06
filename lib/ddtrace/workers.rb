require 'time'

require 'ddtrace/buffer'

module Datadog
  module Workers
    # Asynchronous worker that executes a +Send()+ operation after given
    # seconds. Under the hood, it uses +Concurrent::TimerTask+ so that the thread
    # will perform a task at regular intervals. The thread can be stopped
    # with the +stop()+ method and can start with the +start()+ method.
    class AsyncTransport
      def initialize(span_interval, service_interval, transport, buff_size, trace_task, service_task)
        @trace_task = trace_task
        @service_task = service_task
        @span_interval = span_interval
        @service_interval = service_interval
        @trace_buffer = TraceBuffer.new(buff_size)
        @service_buffer = TraceBuffer.new(buff_size)
        @transport = transport

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
          # pick up the latest services hash (this is a FIFO list)
          # that is different from what we sent before.
          different = services.inject(false) { |acc, elem| elem != @last_flushed_services ? elem : acc }
          if different
            if @service_task.call(different, @transport)
              @last_flushed_services = different.clone
            end
          else
            Datadog::Tracer.log.debug('No new different services, skipping flush.')
          end
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
          @last_flushed_services = nil
          next_send_services = Time.now

          # this loop assumes spans are flushed more often than services
          while @run
            callback_traces
            if Time.now >= next_send_services
              next_send_services = Time.now + @service_interval
              callback_services
            end
            sleep(@span_interval)
          end
        end
      end

      # Stop the timer execution. Tasks already in the queue will be executed.
      def stop
        @run = false
      end

      # Block until executor shutdown is complete or until timeout seconds have passed.
      def join
        @worker.join(10)
      end

      # Enqueue an item in the trace internal buffer. This operation is thread-safe
      # because uses the +TraceBuffer+ data structure.
      def enqueue_trace(trace)
        @trace_buffer.push(trace)
      end

      # Enqueue an item in the service internal buffer. This operation is thread-safe
      # because uses the +TraceBuffer+ data structure.
      def enqueue_service(service)
        return if service == {} # no use to send this, not worth it
        @service_buffer.push(service)
      end
    end
  end
end
