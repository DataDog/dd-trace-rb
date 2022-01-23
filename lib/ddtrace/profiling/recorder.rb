# typed: true
require 'ddtrace/profiling/buffer'
require 'ddtrace/profiling/flush'

module Datadog
  module Profiling
    # Stores profiling events gathered by `Collector`s
    class Recorder
      attr_reader :max_size

      # TODO: Why does the Recorder directly reference the `code_provenance_collector`?
      #
      # For starters, this is weird/a problem because the relationship is supposed to go in the other direction:
      # collectors are supposed to record their results in the `Recorder`, rather than the `Recorder` having to know
      # about individual collectors.
      #
      # But the `code_provenance_collector` is different from other existing and potential collectors because it is not
      # asynchronous. It does not gather data over time and record it as it goes. Instead, you call it once per profile,
      # synchronously, and just use what it spits out.
      #
      # The current design of the `Recorder` is quite tied to the asynchronous model. Modifying our current design
      # to support synchronous collectors is non-trivial, and I decided not to go through with it because we're
      # soon going to replace the `Recorder` and many other existing classes with a
      # [libddprof](https://github.com/datadog/libddprof)-based implementation, and thus I don't think massive refactors
      # are worth it before moving to libddprof.

      def initialize(event_classes, max_size, code_provenance_collector:, last_flush_time: Time.now.utc)
        @buffers = {}
        @last_flush_time = last_flush_time
        @max_size = max_size
        @code_provenance_collector = code_provenance_collector

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

      def flush
        event_count = 0

        event_groups, start, finish = update_time do
          @buffers.collect do |event_class, buffer|
            events = buffer.pop
            next if events.empty?

            event_count += events.length
            EventGroup.new(event_class, events)
          end.compact
        end

        code_provenance = @code_provenance_collector.refresh.generate_json if @code_provenance_collector

        Flush.new(
          start: start,
          finish: finish,
          event_groups: event_groups,
          event_count: event_count,
          code_provenance: code_provenance,
        )
      end

      # NOTE: Remember that if the recorder is being accessed by multiple threads, this is an inherently racy operation.
      def empty?
        @buffers.values.all?(&:empty?)
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
