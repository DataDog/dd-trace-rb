require 'ddtrace/profiling/events/stack'
require 'ddtrace/profiling/pprof/builder'

module Datadog
  module Profiling
    module Pprof
      # Builds a profile from a StackSample
      class StackSample < Builder
        LABEL_KEY_THREAD_ID = 'thread id'.freeze

        def event_group_key(stack_sample)
          [
            stack_sample.thread_id,
            [
              stack_sample.frames.collect(&:to_s),
              stack_sample.total_frame_count
            ]
          ].hash
        end

        def build_sample_types
          [
            build_value_type(
              VALUE_TYPE_WALL,
              VALUE_UNIT_NANOSECONDS
            )
          ]
        end

        def build_sample(stack_sample, values)
          locations = build_locations(
            stack_sample.frames,
            stack_sample.total_frame_count
          )

          Perftools::Profiles::Sample.new(
            location_id: locations.collect(&:id), # TODO: Lazy enumerate?
            value: values,
            label: build_sample_labels(stack_sample)
          )
        end

        def build_sample_values(stack_sample)
          [stack_sample.wall_time_interval_ns]
        end

        def build_sample_labels(stack_sample)
          [
            Perftools::Profiles::Label.new(
              key: string_table.fetch(LABEL_KEY_THREAD_ID),
              str: string_table.fetch(stack_sample.thread_id.to_s)
            )
          ]
        end
      end
    end
  end
end
