require 'ddtrace/utils/sequence'

module Datadog
  module Profiling
    module Pprof
      # Tracks strings and returns IDs
      class StringTable
        def initialize
          @sequence = Utils::Sequence.new
          @ids = { '' => @sequence.next }
        end

        def fetch(string)
          @ids[string.to_s] ||= @sequence.next
        end

        def strings
          @ids.keys
        end
      end
    end
  end
end
