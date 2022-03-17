# typed: true
module Datadog
  module Profiling
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

        if ENV['DD_PROFILING_WIPMEMORY'] == 'true'
          allocation_sampling_probability = Float(ENV['DD_PROFILING_WIPMEMORY_SAMPLING_PROBABILITY'] || 0.001)
          maximum_tracked_objects = Integer(ENV['DD_PROFILING_WIPMEMORY_MAXIMUM_TRACKED'] || 3000)

          Datadog.logger.debug("Allocation and heap profiling enabled, #{allocation_sampling_probability} sampling probability, #{maximum_tracked_objects} max tracked")

          Datadog::Profiling::WipMemory.configure_profiling(
            allocation_sampling_probability,
            maximum_tracked_objects
          )
          Datadog::Profiling::WipMemory.start_allocation_tracing
        end
      end

      def shutdown!
        Datadog.logger.debug('Shutting down profiler')

        collectors.each do |collector|
          collector.enabled = false
          collector.stop(true)
        end

        Datadog::Profiling::WipMemory.stop_allocation_tracing

        scheduler.enabled = false
        scheduler.stop(true)
      end
    end
  end
end
