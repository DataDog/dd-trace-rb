# typed: true
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
      Datadog::Profiling::NativeExtension.start_allocation_tracing
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

      Datadog::Profiling::NativeExtension.stop_allocation_tracing
    end
  end
end
