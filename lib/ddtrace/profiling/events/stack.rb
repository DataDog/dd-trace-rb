# typed: true
require 'ddtrace/profiling/event'

module Datadog
  module Profiling
    module Events
      # Describes a stack profiling event
      class Stack < Event
        attr_reader \
          :hash,
          :frames,
          :total_frame_count,
          :thread_id,
          :trace_id,
          :span_id,
          :trace_resource_container

        def initialize(
          timestamp,
          frames,
          total_frame_count,
          thread_id,
          trace_id,
          span_id,
          trace_resource_container
        )
          super(timestamp)

          @frames = frames
          @total_frame_count = total_frame_count
          @thread_id = thread_id
          @trace_id = trace_id
          @span_id = span_id
          @trace_resource_container = trace_resource_container

          @hash = [
            thread_id,
            trace_id,
            span_id,
            # trace_resource_container is deliberately not included -- events that share the same (trace_id, span_id)
            # pair should also have the same trace_resource_container
            frames.collect(&:hash),
            total_frame_count
          ].hash
        end
      end

      # Describes a stack sample
      class StackSample < Stack
        attr_reader \
          :cpu_time_interval_ns,
          :wall_time_interval_ns

        def initialize(
          timestamp,
          frames,
          total_frame_count,
          thread_id,
          trace_id,
          span_id,
          trace_resource_container,
          cpu_time_interval_ns,
          wall_time_interval_ns
        )
          super(
            timestamp,
            frames,
            total_frame_count,
            thread_id,
            trace_id,
            span_id,
            trace_resource_container
          )

          @cpu_time_interval_ns = cpu_time_interval_ns
          @wall_time_interval_ns = wall_time_interval_ns
        end
      end
    end
  end
end
