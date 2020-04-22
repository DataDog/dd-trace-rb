module Datadog
  module Profiling
    # Describes a sample of some data obtained from the runtime.
    class Event
      attr_reader \
        :timestamp

      def initialize
        @timestamp = Time.now.utc.to_i
      end
    end
  end
end
