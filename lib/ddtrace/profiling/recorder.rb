require 'ddtrace/profiling/buffer'
require 'ddtrace/profiling/flush'

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

      def push(events)
        if events.is_a?(Array)
          # Push multiple events
          event_class = events.first.class
          raise UnknownEventError, event_class unless @buffers.key?(event_class)
          @buffers[event_class].concat(events)
        else
          # Push single event
          event_class = events.class
          raise UnknownEventError, event_class unless @buffers.key?(event_class)
          @buffers[event_class].push(events)
        end
      end

      def pop
        @buffers.collect do |event_class, buffer|
          events = buffer.pop
          next if events.empty?
          Flush.new(event_class, events)
        end.compact
      end

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
