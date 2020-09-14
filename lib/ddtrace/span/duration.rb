require 'ddtrace/utils/time'

module Datadog
  class Span
    # Stateful class used to track and calculate the duration of a Span.
    class Duration
      attr_reader :start_time, :end_time

      def initialize
        @start_time = nil
        @duration_start = nil
        @end_time = nil
        @duration_end = nil
        @wall_clock_duration = false
      end

      # Return whether the duration is started or not
      def started?
        !@start_time.nil?
      end

      # Return whether the duration is finished or not.
      def finished?
        !@end_time.nil?
      end

      def complete?
        started? && finished?
      end

      def start(start_time)
        if start_time
          @start_time = start_time
          @duration_start = start_time
          @wall_clock_duration = true
        else
          @start_time = Time.now.utc
          @duration_start = duration_marker
        end
      end

      def finish(finish_time)
        now = Time.now.utc

        # Provide a default start_time if unset.
        # Using `now` here causes duration to be 0; this is expected
        # behavior when start_time is unknown.
        start(finish_time || now) unless started?

        if finish_time
          @end_time = finish_time
          @duration_start = @start_time
          @duration_end = finish_time
          @wall_clock_duration = true
        else
          @end_time = now
          @duration_end = @wall_clock_duration ? now : duration_marker
        end
      end

      def to_f
        (@duration_end - @duration_start).to_f rescue 0.0
      end

      def duration_marker
        Utils::Time.get_time
      end
    end
  end
end
