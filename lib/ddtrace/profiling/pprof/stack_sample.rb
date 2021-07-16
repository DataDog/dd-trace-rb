require 'ddtrace/ext/profiling'
require 'ddtrace/profiling/events/stack'
require 'ddtrace/profiling/pprof/builder'
require 'ddtrace/profiling/pprof/converter'

module Datadog
  module Profiling
    module Pprof
      # Builds a profile from a StackSample
      #
      # NOTE: This class may appear stateless but is in fact stateful; a new instance should be created for every
      # encoded profile.
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

        def initialize(*_)
          super

          @processed_unique_stacks = 0
          @processed_with_trace_ids = 0
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
            @processed_unique_stacks += 1
            build_sample(group.sample, group.values)
          end
        end

        def build_sample(stack_sample, values)
          locations = builder.build_locations(
            stack_sample.frames,
            stack_sample.total_frame_count
          )

          if ENV['DD_PROFILING_TRACEHACK'] == 'true'
            locations +=
              if (stack_sample.trace_id.nil? || stack_sample.trace_id.zero?) &&
                (stack_sample.span_id.nil? || stack_sample.span_id.zero?)

                builder.build_locations([Profiling::BacktraceLocation.new("❌ No active trace", 0, "")], 1)
              else
                builder.build_locations([Profiling::BacktraceLocation.new("✅ Active trace", 0, "")], 1)
              end
          end

          Perftools::Profiles::Sample.new(
            location_id: locations.collect { |location| location['id'.freeze] },
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

          trace_id = stack_sample.trace_id || 0
          span_id = stack_sample.span_id || 0

          if trace_id != 0 && span_id != 0
            @processed_with_trace_ids += 1

            labels << Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Datadog::Ext::Profiling::Pprof::LABEL_KEY_TRACE_ID),
              str: builder.string_table.fetch(trace_id.to_s)
            )

            labels << Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Datadog::Ext::Profiling::Pprof::LABEL_KEY_SPAN_ID),
              str: builder.string_table.fetch(span_id.to_s)
            )

            trace_resource = stack_sample.trace_resource
            if trace_resource
              trace_resource = trace_resource.resource if trace_resource.span_type == Datadog::Ext::HTTP::TYPE_INBOUND
            end

            if trace_resource && !trace_resource.empty?
              labels << Perftools::Profiles::Label.new(
                key: builder.string_table.fetch(Datadog::Ext::Profiling::Pprof::LABEL_KEY_TRACE_ENDPOINT),
                str: builder.string_table.fetch(trace_resource)
              )
            end
          end

          labels
        end

        def debug_statistics
          "unique stacks: #{@processed_unique_stacks}, of which had active traces: #{@processed_with_trace_ids}"
        end
      end
    end
  end
end
