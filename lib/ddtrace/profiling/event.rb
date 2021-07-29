module Datadog
  module Profiling
    # Describes a sample of some data obtained from the runtime.
    class Event
      attr_reader \
        :timestamp

      def initialize(timestamp = nil)
        @timestamp = timestamp || Time.now.utc.to_f
      end
    end
  end
end
