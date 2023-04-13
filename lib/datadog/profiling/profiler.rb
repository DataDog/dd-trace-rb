module Datadog
  module Profiling
    # Profiling entry point, which coordinates collectors and a scheduler
    class Profiler
      include Datadog::Core::Utils::Forking

      attr_reader \
        :collectors,
        :scheduler

      def initialize(collectors, scheduler)
        @collectors = collectors
        @scheduler = scheduler
      end

      def start
        after_fork! do
          collectors.each(&:reset_after_fork)
          scheduler.reset_after_fork
        end

        collectors.each(&:start)
        scheduler.start
      end

      def shutdown!
        Datadog.logger.debug('Shutting down profiler')

        collectors.each do |collector|
          collector.enabled = false
          collector.stop(true)
        end

        scheduler.enabled = false
        scheduler.stop(true)
      end
    end
  end
end
