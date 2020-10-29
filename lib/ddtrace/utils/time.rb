module Datadog
  module Utils
    # Common database-related utility functions.
    module Time
      PROCESS_TIME_SUPPORTED = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')

      # unneeded for now since we want to fallback to default
      DEFAULT_TIME = :default_time
      REALTIME_WITH_TIMECOP = :realtime_with_timecop
      NOW = :now
      NOW_WITHOUT_MOCK_TIME = :now_without_mock_time

      attr_accessor :time_provider

      module_function

      def get_time
        PROCESS_TIME_SUPPORTED ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : current_time.to_f
      end

      def current_time
        return ::Time.send(NOW) if (@time_provider ||= DEFAULT_TIME) == DEFAULT_TIME

        ::Time.send(alt_time(@time_provider))
      end

      def time_provider=(time_provider)
        @time_provider = time_provider
      end

      def alt_time(time_provider)
        # currenty we only have :default or :realtime_with_timecop as options
        # so we can just have :default act as a general fallback
        if time_provider == REALTIME_WITH_TIMECOP
          (::Time.respond_to?(NOW_WITHOUT_MOCK_TIME) ? NOW_WITHOUT_MOCK_TIME : NOW)
        else
          NOW
        end
      end
    end
  end
end
