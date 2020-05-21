require 'ddtrace/profiling/pprof/message_set'
require 'ddtrace/profiling/pprof/pprof_pb'
require 'ddtrace/profiling/pprof/string_table'

module Datadog
  module Profiling
    module Pprof
      # Generic profile building behavior
      class Builder
        DESC_FRAME_OMITTED = 'frame omitted'.freeze
        DESC_FRAMES_OMITTED = 'frames omitted'.freeze
        VALUE_TYPE_WALL = 'wall'.freeze
        VALUE_UNIT_NANOSECONDS = 'nanoseconds'.freeze

        attr_reader \
          :events,
          :functions,
          :locations,
          :sample_types,
          :samples,
          :string_table

        def initialize(events)
          @events = events
          @profile = nil
          @sample_types = []
          @samples = []
          @mappings = []
          @locations = MessageSet.new
          @functions = MessageSet.new
          @string_table = StringTable.new
        end

        def to_profile
          @profile ||= build_profile(@events)
        end

        def build_profile(events)
          @sample_types = build_sample_types
          @samples = group_events(events) do |event, values|
            build_sample(event, values)
          end
          @mappings = build_mappings

          Perftools::Profiles::Profile.new(
            sample_type: @sample_types,
            sample: @samples,
            mapping: @mappings,
            location: @locations.messages,
            function: @functions.messages,
            string_table: @string_table.strings
          )
        end

        def group_events(events)
          # Event grouping in format:
          # [key, (event, [values, ...])]
          event_groups = {}

          events.each do |event|
            key = event_group_key(event) || rand
            values = build_sample_values(event)

            unless key.nil?
              if event_groups.key?(key)
                # Update values for group
                group_values = event_groups[key][1]
                group_values.each_with_index do |group_value, i|
                  group_values[i] = group_value + values[i]
                end
              else
                # Add new group
                event_groups[key] = [event, values]
              end
            end
          end

          event_groups.collect do |_group_key, group|
            yield(
              # Event
              group[0],
              # Values
              group[1]
            )
          end
        end

        def event_group_key(event)
          raise NotImplementedError
        end

        def build_sample_types
          raise NotImplementedError
        end

        def build_value_type(type, unit)
          Perftools::Profiles::ValueType.new(
            type: string_table.fetch(type),
            unit: string_table.fetch(unit)
          )
        end

        def build_sample(event, values)
          raise NotImplementedError
        end

        def build_sample_values(event)
          raise NotImplementedError
        end

        def build_locations(backtrace_locations, length)
          locations = backtrace_locations.collect do |backtrace_location|
            @locations.fetch(
              # Filename
              backtrace_location.path,
              # Line number
              backtrace_location.lineno,
              # Function name
              backtrace_location.base_label,
              # Build function
              &method(:build_location)
            )
          end

          omitted = length - backtrace_locations.length

          # Add placeholder stack frame if frames were truncated
          if omitted > 0
            desc = omitted == 1 ? DESC_FRAME_OMITTED : DESC_FRAMES_OMITTED
            locations << @locations.fetch(
              '',
              0,
              "#{omitted} #{desc}",
              &method(:build_location)
            )
          end

          locations
        end

        def build_location(id, filename, line_number, function_name = nil)
          Perftools::Profiles::Location.new(
            id: id,
            line: [build_line(
              @functions.fetch(
                filename,
                function_name,
                &method(:build_function)
              ).id,
              line_number
            )]
          )
        end

        def build_line(function_id, line_number)
          Perftools::Profiles::Line.new(
            function_id: function_id,
            line: line_number
          )
        end

        def build_function(id, filename, function_name)
          Perftools::Profiles::Function.new(
            id: id,
            name: @string_table.fetch(function_name),
            filename: @string_table.fetch(filename)
          )
        end

        def build_mappings
          [
            Perftools::Profiles::Mapping.new(
              id: 1,
              filename: @string_table.fetch($PROGRAM_NAME)
            )
          ]
        end
      end
    end
  end
end
