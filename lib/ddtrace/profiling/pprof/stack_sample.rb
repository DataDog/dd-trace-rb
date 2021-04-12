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
          cpu_time_ns: [
            Datadog::Ext::Profiling::Pprof::VALUE_TYPE_CPU,
            Datadog::Ext::Profiling::Pprof::VALUE_UNIT_NANOSECONDS
          ],
          wall_time_ns: [
            Datadog::Ext::Profiling::Pprof::VALUE_TYPE_WALL,
            Datadog::Ext::Profiling::Pprof::VALUE_UNIT_NANOSECONDS
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
          stack_sample.hash
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
          no_value = Datadog::Ext::Profiling::Pprof::SAMPLE_VALUE_NO_VALUE
          values = super(stack_sample)
          values[sample_value_index(:cpu_time_ns)] = stack_sample.cpu_time_interval_ns || no_value
          values[sample_value_index(:wall_time_ns)] = stack_sample.wall_time_interval_ns || no_value
          values
        end

        def build_sample_labels(stack_sample)
          labels = [
            Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Datadog::Ext::Profiling::Pprof::LABEL_KEY_THREAD_ID),
              str: builder.string_table.fetch(stack_sample.thread_id.to_s)
            )
          ]

          unless stack_sample.trace_id.nil? || stack_sample.trace_id.zero?
            labels << Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Datadog::Ext::Profiling::Pprof::LABEL_KEY_TRACE_ID),
              str: builder.string_table.fetch(stack_sample.trace_id.to_s)
            )
          end

          unless stack_sample.span_id.nil? || stack_sample.span_id.zero?
            labels << Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Datadog::Ext::Profiling::Pprof::LABEL_KEY_SPAN_ID),
              str: builder.string_table.fetch(stack_sample.span_id.to_s)
            )
          end

          labels
        end
      end
    end
  end
end
