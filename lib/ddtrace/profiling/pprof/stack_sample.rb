require 'ddtrace/ext/profiling'
require 'ddtrace/profiling/events/stack'
require 'ddtrace/profiling/pprof/builder'
require 'ddtrace/profiling/pprof/converter'

module Datadog
  module Profiling
    module Pprof
      # Builds a profile from a StackSample
      class StackSample < Converter
        SAMPLE_TYPES = {
          wall_time_ns: [
            Ext::Profiling::Pprof::VALUE_TYPE_WALL,
            Ext::Profiling::Pprof::VALUE_UNIT_NANOSECONDS
          ]
        }.freeze

        def self.sample_value_types
          SAMPLE_TYPES
        end

        def add_events!(stack_samples)
          new_samples = build_samples(stack_samples)
          builder.samples.concat(new_samples)
        end

        def stack_sample_group_key(stack_sample)
          [
            stack_sample.thread_id,
            [
              stack_sample.frames.collect(&:to_s),
              stack_sample.total_frame_count
            ]
          ].hash
        end

        def build_samples(stack_samples)
          groups = group_events(stack_samples, &method(:stack_sample_group_key))
          groups.collect do |_group_key, group|
            build_sample(group.sample, group.values)
          end
        end

        def build_sample(stack_sample, values)
          locations = builder.build_locations(
            stack_sample.frames,
            stack_sample.total_frame_count
          )

          Perftools::Profiles::Sample.new(
            location_id: locations.collect(&:id),
            value: values,
            label: build_sample_labels(stack_sample)
          )
        end

        def build_sample_values(stack_sample)
          values = super(stack_sample)
          values[sample_value_index(:wall_time_ns)] = stack_sample.wall_time_interval_ns
          values
        end

        def build_sample_labels(stack_sample)
          [
            Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Ext::Profiling::Pprof::LABEL_KEY_THREAD_ID),
              str: builder.string_table.fetch(stack_sample.thread_id.to_s)
            )
          ]
        end
      end
    end
  end
end
