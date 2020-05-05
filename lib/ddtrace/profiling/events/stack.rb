require 'ddtrace/profiling/event'

module Datadog
  module Profiling
    module Events
      # Describes a stack profiling event
      class Stack < Event
        attr_reader \
          :frames,
          :total_frame_count,
          :thread_id

        def initialize(
          timestamp,
          frames,
          total_frame_count,
          thread_id
        )
          super(timestamp)

          @frames = frames
          @total_frame_count = total_frame_count
          @thread_id = thread_id
        end
      end

      # Describes a stack sample
      class StackSample < Stack
        attr_reader \
          :wall_time_interval_ns

        def initialize(
          timestamp,
          frames,
          total_frame_count,
          thread_id,
          wall_time_interval_ns
        )
          super(
            timestamp,
            frames,
            total_frame_count,
            thread_id
          )

          @wall_time_interval_ns = wall_time_interval_ns
        end
      end

      # Describes a stack sample with exception
      class StackExceptionSample < Stack
        attr_reader \
          :exception

        def initialize(
          timestamp,
          frames,
          total_frame_count,
          thread_id,
          exception
        )
          super(
            timestamp,
            frames,
            total_frame_count,
            thread_id,
          )

          @exception = exception
        end
      end
    end
  end
end
