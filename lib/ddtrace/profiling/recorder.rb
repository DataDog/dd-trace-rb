require 'ddtrace/profiling/buffer'

module Datadog
  module Profiling
    # Profiling buffer that stores profiling events. The buffer has a maximum size and when
    # the buffer is full, a random event is discarded. This class is thread-safe.
    class Recorder
      def initialize(event_classes, max_size)
        @buffers = {}

        # Add a buffer for each class
        event_classes.each do |event_class|
          @buffers[event_class] = Profiling::Buffer.new(max_size)
        end
      end

      def push(event)
        raise UnknownEventError, event.class unless @buffers.key?(event.class)
        @buffers[event.class].push(event)
      end

      def pop
        @buffers.collect do |event_class, buffer|
          events = buffer.pop
          next if events.empty?
          Flush.new(event_class, events)
        end.compact
      end

      Flush = Struct.new(:event_class, :events).freeze

      # Error when event of an unknown type is used with the Recorder
      class UnknownEventError < StandardError
        attr_reader :event_class

        def initialize(event_class)
          @event_class = event_class
        end

        def message
          @message ||= "Unknown event class '#{event_class}' for profiling recorder."
        end
      end
    end
  end
end
