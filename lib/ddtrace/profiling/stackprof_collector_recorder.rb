require 'stackprof'

module Datadog
  module Profiling
    # Provides an object that serves at the same time as a collector (using stackprof) and
    # as a recorder (collects the stackprof results)
    class StackProfCollectorRecorder
      def initialize
        @recorder = Datadog::Profiling::Recorder.new(
          [Datadog::Profiling::Events::StackSample],
          0 # no max size
        )
        @stack_sample_event_recorder = @recorder[Datadog::Profiling::Events::StackSample]

        # Cache this proc, since it's pretty expensive to keep recreating it
        @build_backtrace_location = method(:build_backtrace_location).to_proc

        @needs_flushing = false
      end

      def start
        StackProf.start(mode: :wall, raw: true, aggregate: false)
        Datadog.logger.debug("Started stackprof profiling")
        @needs_flushing = true
      end

      def stop(*_)
        StackProf.stop
        Datadog.logger.debug("Stopped stackprof profiling")
      end

      def enabled=(*_)
      end

      def empty?
        !@needs_flushing
      end

      def flush
        @needs_flushing = false

        was_running = StackProf.running?
        StackProf.stop if was_running
        profile = StackProf.results
        start if was_running

        Datadog.logger.debug "Flushing stackprof profile with"
        StackProf::Report.new(profile).print_text

        profile_to_recorder(profile)
        Datadog.logger.debug "Successfully put stackprof results into recorder"

        @recorder.flush
      end

      private

      def profile_to_recorder(profile)
        frames = profile.fetch(:frames)
        raw_samples = profile.fetch(:raw)

        events = []

        sample_position = 0
        while sample_position < raw_samples.size
          length = raw_samples[sample_position]
          stack_start_position = sample_position + 1
          stack_end_position = sample_position + length
          count_position = stack_end_position + 1

          the_samples = raw_samples[stack_start_position..stack_end_position]
          count = raw_samples[count_position]

          events << Events::StackSample.new(
            nil,
            samples_to_locations(frames, the_samples),
            the_samples.size,
            1, # fake thread id,
            nil, # trace_id
            nil, # span_id
            nil, # no cpu time
            1000000 * count, # sample rate for stackprof * times seen
          )

          sample_position = count_position + 1
        end

        @recorder.push(events)
      end

      def samples_to_locations(frames, samples)
        samples.map do |sample|
          frame = frames.fetch(sample)

          @stack_sample_event_recorder.cache(:backtrace_locations).fetch(
            frame.fetch(:name),
            frame[:line] || 0,
            frame.fetch(:file),
            &@build_backtrace_location
          )
        end
      end

      def build_backtrace_location(_id, base_label, lineno, path)
        string_table = @stack_sample_event_recorder.string_table

        Profiling::BacktraceLocation.new(
          string_table.fetch_string(base_label),
          lineno,
          string_table.fetch_string(path)
        )
      end
    end
  end
end
