require_relative '../ext'

module Datadog
  module Profiling
    module Pprof
      # Base class for converters that convert profiling events to pprof
      class Converter
        attr_reader \
          :builder

        # Override in child class to define sample types
        # this converter uses when building samples.
        def self.sample_value_types
          raise NotImplementedError
        end

        def initialize(builder, sample_type_mappings)
          @builder = builder
          @sample_type_mappings = sample_type_mappings
        end

        def group_events(events)
          # Event grouping in format:
          # [key, EventGroup]
          event_groups = {}

          # Aggregate each event into a group
          # with identical properties, but different values.
          events.each do |event|
            key = yield(event)
            values = build_event_values(event)

            unless key.nil?
              if event_groups.key?(key)
                # Update existing group from event
                update_group(event_groups[key], event, values)
              else
                # Add new group
                event_groups[key] = new_group(event, values)
              end
            end
          end

          event_groups
        end

        def add_events!(events)
          raise NotImplementedError
        end

        def sample_value_index(type)
          index = @sample_type_mappings[type]
          raise UnknownSampleTypeMappingError, type unless index

          index
        end

        def build_event_values(event)
          # Build a value array that matches the length of the sample types
          # Populate all values with "no value" by default
          Array.new(@sample_type_mappings.length, Profiling::Ext::Pprof::SAMPLE_VALUE_NO_VALUE)
        end

        def debug_statistics
          # Empty; can be used by subclasses to report a string containing debug statistics to be logged
        end

        # Represents a grouped event
        # 'sample' is an example event object from the group.
        # 'values' is the summation of the group's sample values
        EventGroup = Struct.new(:sample, :values)

        # Error when the mapping of a sample type to value index is unknown
        class UnknownSampleTypeMappingError < StandardError
          attr_reader :type

          def initialize(type)
            @type = type
          end

          def message
            "Mapping for sample value type '#{type}' to index is unknown."
          end
        end

        protected

        def new_group(event, values)
          EventGroup.new(event, values)
        end

        def update_group(event_group, event, values)
          # Update values for group
          group_values = event_group.values
          group_values.each_with_index do |group_value, i|
            group_values[i] = group_value + values[i]
          end
        end
      end
    end
  end
end
