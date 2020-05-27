require 'ddtrace/profiling/flush'
require 'ddtrace/profiling/pprof/message_set'
require 'ddtrace/profiling/pprof/string_table'

require 'ddtrace/profiling/pprof/pprof_pb'

module Datadog
  module Profiling
    module Pprof
      # Accumulates profile data and produces a Perftools::Profiles::Profile
      class Builder
        DESC_FRAME_OMITTED = 'frame omitted'.freeze
        DESC_FRAMES_OMITTED = 'frames omitted'.freeze

        attr_reader \
          :functions,
          :locations,
          :mappings,
          :sample_types,
          :samples,
          :string_table

        def initialize
          @functions = MessageSet.new(1)
          @locations = MessageSet.new(1)
          @mappings = MessageSet.new(1)
          @sample_types = MessageSet.new
          @samples = []
          @string_table = StringTable.new
        end

        def build_profile
          Perftools::Profiles::Profile.new(
            sample_type: @sample_types.messages,
            sample: @samples,
            mapping: @mappings.messages,
            location: @locations.messages,
            function: @functions.messages,
            string_table: @string_table.strings
          )
        end

        def build_value_type(type, unit)
          Perftools::Profiles::ValueType.new(
            type: @string_table.fetch(type),
            unit: @string_table.fetch(unit)
          )
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
      end
    end
  end
end
