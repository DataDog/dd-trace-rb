module Datadog
  module Ext
    module Profiling
      ENV_MAX_FRAMES = 'DD_PROFILING_MAX_FRAMES'.freeze
      ENV_MAX_TIME_USAGE_PCT = 'DD_PROFILING_MAX_TIME_USAGE_PCT'.freeze
      ENV_IGNORE_PROFILER = 'DD_PROFILING_IGNORE_PROFILER'.freeze

      module Pprof
        LABEL_KEY_THREAD_ID = 'thread id'.freeze
        SAMPLE_VALUE_NO_VALUE = 0
        VALUE_TYPE_WALL = 'wall'.freeze
        VALUE_UNIT_NANOSECONDS = 'nanoseconds'.freeze
      end
    end
  end
end
