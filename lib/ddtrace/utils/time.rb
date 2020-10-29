module Datadog
  module Utils
    # Common database-related utility functions.
    module Time
      PROCESS_TIME_SUPPORTED = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')

      DEFAULT_TIME = :default_time
      REALTIME_WITH_TIMECOP = :realtime_with_timecop
      NOW = :now
      NOW_WITHOUT_MOCK_TIME = :now_without_mock_time

      attr_writer :now
      attr_writer :time_provider

      module_function

      def get_time
        PROCESS_TIME_SUPPORTED ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : current_time.to_f
      end

      def current_time
        ::Time.send(now)
      end

      def now
        @now ||= begin
          @time_provider ||= Datadog.configuration.time_provider

          if @time_provider == DEFAULT_TIME
            NOW
          elsif @time_provider == REALTIME_WITH_TIMECOP
            (::Time.respond_to?(NOW_WITHOUT_MOCK_TIME) ? NOW_WITHOUT_MOCK_TIME : NOW)
          end
        end
      end
    end
  end
end
