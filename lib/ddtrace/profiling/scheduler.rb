require 'ddtrace/utils/time'

require 'ddtrace/worker'
require 'ddtrace/workers/polling'

module Datadog
  module Profiling
    # Periodically (every DEFAULT_INTERVAL_SECONDS) takes data from the `Recorder` and pushes them to all configured
    # `Exporter`s. Runs on its own background thread.
    class Scheduler < Worker
      include Workers::Polling

      DEFAULT_INTERVAL_SECONDS = 60
      MIN_INTERVAL_SECONDS = 0

      attr_reader \
        :exporters,
        :recorder

      def initialize(
        recorder,
        exporters,
        # Should we flush immediately on the next call to flush_events, or loop/sleep at least once before doing it?
        skip_next_flush: true,
        fork_policy: Workers::Async::Thread::FORK_POLICY_RESTART, # Restart in forks by default
        interval: DEFAULT_INTERVAL_SECONDS,
        enabled: true
      )
        @recorder = recorder
        @exporters = [exporters].flatten
        @skip_next_flush = skip_next_flush

        # Workers::Async::Thread settings
        self.fork_policy = fork_policy

        # Workers::IntervalLoop settings
        self.loop_base_interval = interval

        # Workers::Polling settings
        self.enabled = enabled
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
        recorder.flush

        # Force loop/sleep before next report
        @skip_next_flush = true
      end

      private

      def flush_and_wait
        run_time = Datadog::Utils::Time.measure do
          flush_events
        end

        # Update wait time to try to wake consistently on time.
        # Don't drop below the minimum interval.
        self.loop_wait_time = [loop_base_interval - run_time, MIN_INTERVAL_SECONDS].max
      end

      def flush_events
        # When a scheduler gets created (or reset), we don't want it to immediately try to flush; we want it to wait for
        # the loop wait time first. This avoids an issue where the scheduler reported a mostly-empty profile if the
        # application just started but this thread took a bit longer so there's already samples in the recorder.
        if skip_next_flush?
          @skip_next_flush = false
          return
        end

        # Get events from recorder
        flush = recorder.flush

        # Send events to each exporter
        if flush.event_count > 0
          exporters.each do |exporter|
            begin
              exporter.export(flush)
            rescue StandardError => e
              Datadog.logger.error(
                "Unable to export #{flush.event_count} profiling events. Cause: #{e} Location: #{e.backtrace.first}"
              )
            end
          end
        end

        flush
      end

      def skip_next_flush?
        @skip_next_flush
      end
    end
  end
end
