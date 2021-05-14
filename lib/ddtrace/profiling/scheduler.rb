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
        fork_policy: Workers::Async::Thread::FORK_POLICY_RESTART, # Restart in forks by default
        interval: DEFAULT_INTERVAL_SECONDS,
        enabled: true
      )
        @recorder = recorder
        @exporters = [exporters].flatten

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
      end

      # Configure Workers::IntervalLoop to not report immediately when scheduler starts
      #
      # When a scheduler gets created (or reset), we don't want it to immediately try to flush; we want it to wait for
      # the loop wait time first. This avoids an issue where the scheduler reported a mostly-empty profile if the
      # application just started but this thread took a bit longer so there's already samples in the recorder.
      def loop_wait_before_first_iteration?
        true
      end

      def work_pending?
        !recorder.empty?
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
        @times_flushed ||= 0
        @times_flushed += 1
        current_thread = Thread.current

        before_timing = Time.now.utc
        before_cpu_time = current_thread.respond_to?(:cpu_time) ? current_thread.cpu_time : 0

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

        if ENV['DD_PROFILING_FLUSHTIME'] == 'true'
          after_timing = ((Time.now.utc - before_timing) * 1000)
          after_cpu_time = (((current_thread.respond_to?(:cpu_time) ? current_thread.cpu_time : 0) - before_cpu_time) * 1000)

          Datadog.logger.info("Finished reporting profile, took #{after_timing} ms (cpu #{after_cpu_time} ms)")
        end

        if ENV['DD_PROFILING_LOOPFLUSH'] && Integer(ENV['DD_PROFILING_LOOPFLUSH']) == @times_flushed
          loop do
            begin
              exporters.first.export(flush)
            rescue StandardError => e
              Datadog.logger.error(
                "Unable to export #{flush.event_count} profiling events. Cause: #{e} Location: #{e.backtrace.first}"
              )
            end
          end
        end

        flush
      end
    end
  end
end
