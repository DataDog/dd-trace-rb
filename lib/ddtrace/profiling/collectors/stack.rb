require 'ddtrace/profiling/backtrace_location'
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
        THREAD_LAST_CPU_TIME_KEY = :datadog_profiler_last_cpu_time

        attr_reader \
          :ignore_thread,
          :max_frames,
          :max_time_usage_pct,
          :recorder

        def initialize(recorder, options = {})
          @recorder = recorder
          @max_frames = options[:max_frames] || DEFAULT_MAX_FRAMES
          @ignore_thread = options[:ignore_thread]
          @max_time_usage_pct = options[:max_time_usage_pct] || DEFAULT_MAX_TIME_USAGE_PCT

          # Workers::Async::Thread settings
          # Restart in forks by default
          self.fork_policy = options[:fork_policy] || Workers::Async::Thread::FORK_POLICY_RESTART

          # Workers::IntervalLoop settings
          self.loop_base_interval = options[:interval] || MIN_INTERVAL

          # Workers::Polling settings
          self.enabled = options[:enabled] == true
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
          last_wall_time = if instance_variable_defined?(:@last_wall_time)
                             @last_wall_time
                           else
                             current_wall_time
                           end

          wall_time_interval_ns = ((current_wall_time - last_wall_time).round(9) * 1e9).to_i
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

          # Convert backtrace locations into structs
          locations = convert_backtrace_locations(locations)

          thread_id = thread.respond_to?(:native_thread_id) ? thread.native_thread_id : nil
          thread_id ||= thread.object_id

          Events::StackSample.new(
            nil,
            locations,
            stack_size,
            thread_id,
            get_cpu_time_interval!(thread),
            wall_time_interval_ns
          )
        end

        def get_cpu_time_interval!(thread)
          # Return if we can't get the current CPU time
          return unless thread.respond_to?(:cpu_time)
          current_cpu_time_ns = thread.cpu_time(:nanosecond)
          return unless current_cpu_time_ns

          last_cpu_time_ns = (thread[THREAD_LAST_CPU_TIME_KEY] || current_cpu_time_ns)
          interval = current_cpu_time_ns - last_cpu_time_ns

          # Update CPU time for thread
          thread[THREAD_LAST_CPU_TIME_KEY] = current_cpu_time_ns

          # Return interval
          interval
        end

        def compute_wait_time(used_time)
          used_time_ns = used_time * 1e9

          interval = (used_time_ns / (max_time_usage_pct / 100.0)) - used_time_ns
          [interval / 1e9, MIN_INTERVAL].max
        end

        # Convert backtrace locations into structs
        # Re-use old backtrace location objects if they already exist in the buffer
        def convert_backtrace_locations(locations)
          string_table = recorder[Events::StackSample].string_table

          locations.collect do |location|
            # Re-use existing BacktraceLocation if identical copy, otherwise build a new one.
            recorder[Events::StackSample].cache(:backtrace_locations).fetch(
              # Function name
              string_table.fetch_string(location.base_label),
              # Line number
              location.lineno,
              # Filename
              string_table.fetch_string(location.path),
              # Build function
              &method(:build_backtrace_location)
            )
          end
        end

        def build_backtrace_location(_id, base_label, lineno, path)
          Profiling::BacktraceLocation.new(
            base_label,
            lineno,
            path
          )
        end
      end
    end
  end
end
