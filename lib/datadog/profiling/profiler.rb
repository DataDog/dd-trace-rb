module Datadog
  module Profiling
    # Profiling entry point, which coordinates the worker and scheduler threads
    class Profiler
      include Datadog::Core::Utils::Forking

      private

      attr_reader :worker, :scheduler

      public

      def initialize(worker:, scheduler:)
        @worker = worker
        @scheduler = scheduler
      end

      def start
        after_fork! do
          worker.reset_after_fork
          scheduler.reset_after_fork
        end

        worker.start
        scheduler.start
      end

      def shutdown!
        Datadog.logger.debug('Shutting down profiler')

        worker.enabled = false
        worker.stop(true)

        scheduler.enabled = false
        scheduler.stop(true)
      end
    end
  end
end
