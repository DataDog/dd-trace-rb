require_relative '../ext'
require_relative '../events/stack'
require_relative 'builder'
require_relative 'converter'

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
            Profiling::Ext::Pprof::VALUE_TYPE_CPU,
            Profiling::Ext::Pprof::VALUE_UNIT_NANOSECONDS
          ],
          wall_time_ns: [
            Profiling::Ext::Pprof::VALUE_TYPE_WALL,
            Profiling::Ext::Pprof::VALUE_UNIT_NANOSECONDS
          ]
        }.freeze

        def self.sample_value_types
          SAMPLE_TYPES
        end

        def initialize(*_)
          super

          @most_recent_trace_samples = {}
          @processed_unique_stacks = 0
          @processed_with_trace = 0
        end

        def add_events!(stack_samples)
          new_samples = build_samples(stack_samples)
          builder.samples.concat(new_samples)
        end

        def stack_sample_group_key(stack_sample)
          # We want to make sure we have the most recent sample for any trace.
          # (This is done here to save an iteration over all samples.)
          update_most_recent_trace_sample(stack_sample)

          stack_sample.hash
        end

        # Track the most recent sample for each trace (identified by root span id)
        def update_most_recent_trace_sample(stack_sample)
          return unless stack_sample.root_span_id && stack_sample.trace_resource

          # Update trace resource with most recent value
          if (most_recent_trace_sample = @most_recent_trace_samples[stack_sample.root_span_id])
            if most_recent_trace_sample.timestamp < stack_sample.timestamp
              @most_recent_trace_samples[stack_sample.root_span_id] = stack_sample
            end
          else
            # Add trace resource
            @most_recent_trace_samples[stack_sample.root_span_id] = stack_sample
          end
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

          Perftools::Profiles::Sample.new(
            location_id: locations.collect { |location| location['id'.freeze] },
            value: values,
            label: build_sample_labels(stack_sample)
          )
        end

        def build_event_values(stack_sample)
          no_value = Profiling::Ext::Pprof::SAMPLE_VALUE_NO_VALUE
          values = super(stack_sample)
          values[sample_value_index(:cpu_time_ns)] = stack_sample.cpu_time_interval_ns || no_value
          values[sample_value_index(:wall_time_ns)] = stack_sample.wall_time_interval_ns || no_value
          values
        end

        def build_sample_labels(stack_sample)
          labels = [
            Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Profiling::Ext::Pprof::LABEL_KEY_THREAD_ID),
              str: builder.string_table.fetch(stack_sample.thread_id.to_s)
            )
          ]

          root_span_id = stack_sample.root_span_id || 0
          span_id = stack_sample.span_id || 0

          if root_span_id != 0 && span_id != 0
            @processed_with_trace += 1

            labels << Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Profiling::Ext::Pprof::LABEL_KEY_LOCAL_ROOT_SPAN_ID),
              str: builder.string_table.fetch(root_span_id.to_s)
            )

            labels << Perftools::Profiles::Label.new(
              key: builder.string_table.fetch(Profiling::Ext::Pprof::LABEL_KEY_SPAN_ID),
              str: builder.string_table.fetch(span_id.to_s)
            )

            # Use most up-to-date trace resource, if available.
            # Otherwise, use the trace resource provided.
            trace_resource = @most_recent_trace_samples.fetch(stack_sample.root_span_id, stack_sample).trace_resource

            if trace_resource && !trace_resource.empty?
              labels << Perftools::Profiles::Label.new(
                key: builder.string_table.fetch(Profiling::Ext::Pprof::LABEL_KEY_TRACE_ENDPOINT),
                str: builder.string_table.fetch(trace_resource)
              )
            end
          end

          labels
        end

        def debug_statistics
          "unique stacks: #{@processed_unique_stacks}, of which had active traces: #{@processed_with_trace}"
        end
      end
    end
  end
end
