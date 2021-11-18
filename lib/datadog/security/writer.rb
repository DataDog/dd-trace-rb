require 'datadog/security/worker'

module Datadog
  module Security
    # Event writer
    class Writer
      def initialize(options = {})
        @mutex_after_fork = Mutex.new
        @pid = nil
        @stopped = false
      end

      def start
        @mutex_after_fork.synchronize do
          return false if @stopped

          pid = Process.pid
          return if @worker && pid == @pid

          @pid = pid

          start_worker
          true
        end
      end

      def start_worker
        @trace_handler = ->(items, transport) { send_spans(items, transport) }
        @worker = Datadog::Security::Worker.new

        @worker.start
      end

      def stop
        @mutex_after_fork.synchronize { stop_worker }
      end

      def stop_worker
        @stopped = true

        return if @worker.nil?

        @worker.stop
        @worker = nil

        true
      end

      private :start_worker, :stop_worker

      def write(events)
        start if @worker.nil? || @pid != Process.pid

        worker_local = @worker

        if worker_local
          worker_local.enqueue(events)
        elsif !@stopped
          Datadog.logger.debug('Writer either failed to start or was stopped before #write could complete')
        end
      end
    end
  end
end
