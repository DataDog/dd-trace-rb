module Datadog
  module Profiling
    # Represents a collection of events of a specific type being flushed.
    Flush = Struct.new(:event_class, :events).freeze
  end
end
