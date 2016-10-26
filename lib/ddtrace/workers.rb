require 'ddtrace/buffer'

module Datadog
  module Workers
    # Asynchronous worker that executes a +Send()+ operation after given
    # seconds. Under the hood, it uses +Concurrent::TimerTask+ so that the thread
    # will perform a task at regular intervals. The thread can be stopped
    # with the +stop()+ method and can start with the +start()+ method.
    class AsyncTransport
      def initialize(interval, transport, buff_size, &task)
        @task = task
        @interval = interval
        @buffer = TraceBuffer.new(buff_size)
        @transport = transport

        @worker = nil
        @run = true
      end

      # Callback function that executes the +send()+ method. After the exeuction,
      # it reschedules itself using the internal +TimerTask+.
      def callback
        return if @buffer.empty?

        begin
          items = @buffer.pop()
          @task.call(items, @transport)
        rescue StandardError => e
          # ensures that the thread will not die because of an exception.
          # TODO[manu]: findout the reason and reschedule the send if it's not
          # a fatal exception
          Datadog::Tracer.log.error("Error during the flush: dropped #{items.length} items. Cause: #{e}")
        end
      end

      # Start the timer execution.
      def start
        @run = true
        @worker = Thread.new() do
          Datadog::Tracer.log.debug("Starting thread in the process: #{Process.pid}")
          while @run
            callback
            sleep(@interval)
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

      # Enqueue an item in the internal buffer. This operation is thread-safe
      # because uses the +TraceBuffer+ data structure.
      def enqueue(item)
        @buffer.push(item)
      end
    end
  end
end
