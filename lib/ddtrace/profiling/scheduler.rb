require 'ddtrace/utils/time'

require 'ddtrace/worker'
require 'ddtrace/workers/polling'

module Datadog
  module Profiling
    # Pulls and exports profiling data on an async interval basis
    class Scheduler < Worker
      include Workers::Polling

      DEFAULT_INTERVAL = 60
      MIN_INTERVAL = 0

      attr_reader \
        :exporters,
        :recorder

      def initialize(recorder, exporters, options = {})
        @recorder = recorder
        @exporters = [exporters].flatten

        # Workers::Async::Thread settings
        # Restart in forks by default
        self.fork_policy = options.fetch(:fork_policy, Workers::Async::Thread::FORK_POLICY_RESTART)

        # Workers::IntervalLoop settings
        self.loop_base_interval = options.fetch(:interval, DEFAULT_INTERVAL)

        # Workers::Polling settings
        self.enabled = options.fetch(:enabled, false)
      end

      def start
        perform
      end

      def perform
        flush_and_wait
      end

      def loop_back_off?
        false
      end

      def after_fork
        # Clear recorder's buffers by flushing events.
        # Objects from parent process will copy-on-write,
        # and we don't want to send events for the wrong process.
        recorder.pop
      end

      def flush_and_wait
        run_time = Datadog::Utils::Time.measure do
          flush_events
        end

        # Update wait time to try to wake consistently on time.
        # Don't drop below the minimum interval.
        self.loop_wait_time = [loop_base_interval - run_time, MIN_INTERVAL].max
      end

      def flush_events
        # Get events from recorder
        events = recorder.pop
        num_events = events.inject(0) { |sum, flush| sum + flush.events.length }
        return unless num_events > 0

        # Send events to each exporter
        exporters.each do |exporter|
          begin
            exporter.export(events)
          rescue StandardError => e
            error_details = "Cause: #{e} Location: #{e.backtrace.first}"
            Datadog.logger.error("Unable to export #{num_events} profiling events. #{error_details}")
          end
        end

        num_events
      end
    end
  end
end
