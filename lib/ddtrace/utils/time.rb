module Datadog
  module Utils
    # Common database-related utility functions.
    module Time
      PROCESS_TIME_SUPPORTED = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')
      
      DEFAULT_TIME = :default_time.freeze
      REALTIME_WITH_TIMECOP = :realtime_with_timecop.freeze
      NOW = :now.freeze
      NOW_WITHOUT_MOCK_TIME = :now_without_mock_time.freeze


      attr_writer :now
      attr_writer :time_provider

      module_function

      def get_time
        PROCESS_TIME_SUPPORTED ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : current_time
      end

      def current_time
        ::Time.send(now).to_f
      end

      def now
        @now ||= do 
          @time_provider ||= Datadog.configuration.time_provider

          if @time_provider == DEFAULT_TIME
            return NOW
          elsif @time_provider == REALTIME_WITH_TIMECOP
            return (::Time.respond_to?(NOW_WITHOUT_MOCK_TIME) ? NOW_WITHOUT_MOCK_TIME : NOW)
          end
        end
      end
    end
  end
end
