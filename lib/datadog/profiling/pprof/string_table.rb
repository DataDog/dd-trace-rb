# typed: strict
require 'datadog/core/utils/string_table'

module Datadog
  module Profiling
    module Pprof
      # Tracks strings and returns IDs
      class StringTable < Core::Utils::StringTable; end
    end
  end
end
