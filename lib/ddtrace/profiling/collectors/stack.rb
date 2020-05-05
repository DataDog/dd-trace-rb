require 'ddtrace/profiling/events/stack'
require 'ddtrace/utils/time'
require 'ddtrace/worker'
require 'ddtrace/workers/polling'

module Datadog
  module Profiling
    module Collectors
      # Pulls and exports profiling data on an async interval basis
      class Stack < Worker
        include Workers::Polling

        DEFAULT_MAX_FRAMES = 128
        DEFAULT_MAX_TIME_USAGE_PCT = 2.0
        MIN_INTERVAL = 0.01

        attr_reader \
          :ignore_thread,
          :max_frames,
          :max_time_usage_pct,
          :recorder

        def initialize(recorder, options = {})
          @recorder = recorder
          @max_frames = options.fetch(:max_frames, DEFAULT_MAX_FRAMES)
          @ignore_thread = options.fetch(:ignore_thread, nil)
          @max_time_usage_pct = options.fetch(:max_time_usage_pct, DEFAULT_MAX_TIME_USAGE_PCT)

          # Workers::Async::Thread settings
          # Restart in forks by default
          self.fork_policy = options.fetch(:fork_policy, Workers::Async::Thread::FORK_POLICY_RESTART)

          # Workers::IntervalLoop settings
          self.loop_base_interval = options.fetch(:interval, MIN_INTERVAL)

          # Workers::Polling settings
          self.enabled = options.fetch(:enabled, false)
        end

        def start
          @last_wall_time = Datadog::Utils::Time.get_time
          perform
        end

        def perform
          collect_and_wait
        end

        def loop_back_off?
          false
        end

        def last_wall_time
          @last_wall_time ||= Datadog::Utils::Time.get_time
        end

        def collect_and_wait
          run_time = Datadog::Utils::Time.measure do
            collect_events
          end

          # Update wait time to throttle profiling
          self.loop_wait_time = compute_wait_time(run_time)
        end

        def collect_events
          events = []

          # Compute wall time interval
          current_wall_time = Datadog::Utils::Time.get_time
          wall_time_interval_ns = (current_wall_time - last_wall_time) * 1e9
          @last_wall_time = current_wall_time

          # Collect backtraces from each thread
          Thread.list.each do |thread|
            next unless thread.alive?
            next if ignore_thread.is_a?(Proc) && ignore_thread.call(thread)

            event = collect_thread_event(thread, wall_time_interval_ns)
            events << event unless event.nil?
          end

          # Send events to recorder
          recorder.push(events) unless events.empty?

          events
        end

        def collect_thread_event(thread, wall_time_interval_ns)
          locations = thread.backtrace_locations
          return if locations.nil?

          # Get actual stack size then trim the stack
          stack_size = locations.length
          locations = locations[0..(max_frames - 1)]

          Events::StackSample.new(
            nil,
            locations,
            stack_size,
            thread.object_id,
            wall_time_interval_ns
          )
        end

        def compute_wait_time(used_time)
          used_time_ns = used_time * 1e9

          interval = (used_time_ns / (max_time_usage_pct / 100.0)) - used_time_ns
          [interval / 1e9, MIN_INTERVAL].max
        end
      end
    end
  end
end
