require_relative '../event'

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
          :root_span_id,
          :span_id,
          :trace_resource

        def initialize(
          timestamp,
          frames,
          total_frame_count,
          thread_id,
          root_span_id,
          span_id,
          trace_resource
        )
          super(timestamp)

          @frames = frames
          @total_frame_count = total_frame_count
          @thread_id = thread_id
          @root_span_id = root_span_id
          @span_id = span_id
          @trace_resource = trace_resource

          @hash = [
            thread_id,
            root_span_id,
            span_id,
            # trace_resource is deliberately not included -- events that share the same (root_span_id, span_id) refer
            # to the same trace
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
          root_span_id,
          span_id,
          trace_resource,
          cpu_time_interval_ns,
          wall_time_interval_ns
        )
          super(
            timestamp,
            frames,
            total_frame_count,
            thread_id,
            root_span_id,
            span_id,
            trace_resource
          )

          @cpu_time_interval_ns = cpu_time_interval_ns
          @wall_time_interval_ns = wall_time_interval_ns
        end
      end
    end
  end
end
