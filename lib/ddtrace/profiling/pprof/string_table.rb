require 'ddtrace/utils/string_table'

module Datadog
  module Profiling
    module Pprof
      # Tracks strings and returns IDs
      class StringTable < Utils::StringTable; end
    end
  end
end
