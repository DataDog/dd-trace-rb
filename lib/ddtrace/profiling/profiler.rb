module Datadog
  # Generates profiles and transmits them to Datadog
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
      collectors.each do |collector|
        collector.enabled = false
        collector.stop(true)
      end

      scheduler.enabled = false
      scheduler.stop(true)
    end
  end
end
