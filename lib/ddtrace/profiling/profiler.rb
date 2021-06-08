module Datadog
  # Profiling entry point, which coordinates collectors and a scheduler
  class Profiler
    attr_reader \
      :collectors,
      :scheduler

    def initialize(collectors, scheduler)
      @collectors = collectors
      @scheduler = scheduler
    end

    def start
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
