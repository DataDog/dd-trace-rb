require_relative 'buffer'
require_relative 'encoding/profile'

module Datadog
  module Profiling
    # Stores profiling events gathered by the `Stack` collector
    class OldRecorder
      attr_reader :max_size

      def initialize(
        event_classes,
        max_size,
        last_flush_time: Time.now.utc
      )
        @buffers = {}
        @last_flush_time = last_flush_time
        @max_size = max_size

        # Add a buffer for each class
        event_classes.each do |event_class|
          @buffers[event_class] = Profiling::Buffer.new(max_size)
        end

        # Event classes can only be added ahead of time
        @buffers.freeze
      end

      def [](event_class)
        @buffers[event_class]
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

      def serialize
        event_count = 0

        event_groups, start, finish = update_time do
          @buffers.collect do |event_class, buffer|
            events = buffer.pop
            next if events.empty?

            event_count += events.length
            EventGroup.new(event_class, events)
          end.compact
        end

        return if event_count.zero? # We don't want to report empty profiles

        encoded_pprof =
          Datadog::Profiling::Encoding::Profile::Protobuf.encode(
            event_count: event_count,
            event_groups: event_groups,
            start: start,
            finish: finish,
          )

        [start, finish, encoded_pprof]
      end

      def reset_after_fork
        Datadog.logger.debug('Resetting OldRecorder in child process after fork')

        # NOTE: A bit of a heavy-handed approach, but it doesn't happen often and this class will be removed soon anyway
        serialize
        nil
      end

      # Error when event of an unknown type is used with the OldRecorder
      class UnknownEventError < StandardError
        attr_reader :event_class

        def initialize(event_class)
          @event_class = event_class
        end

        def message
          @message ||= "Unknown event class '#{event_class}' for profiling recorder."
        end
      end

      private

      def update_time
        start = @last_flush_time
        result = yield
        @last_flush_time = Time.now.utc

        # Return event groups, start time, finish time
        [result, start, @last_flush_time]
      end
    end
  end
end
