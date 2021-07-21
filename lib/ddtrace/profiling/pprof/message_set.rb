# typed: true
require 'ddtrace/utils/object_set'

module Datadog
  module Profiling
    module Pprof
      # Acts as a unique dictionary of protobuf messages
      class MessageSet < Utils::ObjectSet
        def messages
          objects
        end
      end
    end
  end
end
