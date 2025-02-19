# frozen_string_literal: true

module Datadog
  module AppSec
    module ActionsHandler
      # Module that collects the stack trace into formatted hash
      module StackTraceCollection
        module_function

        def collect(max_depth, top_percent)
          filtered_locations = caller_locations&.reject { |location| location.to_s.include?('lib/datadog') } || []

          skip_locations =
            if max_depth == 0 || filtered_locations.size <= max_depth
              (0...0)
            else
              top_limit = (max_depth * top_percent / 100.0).round
              bottom_limit = filtered_locations.size - (max_depth - top_limit)
              (top_limit...bottom_limit)
            end
          filtered_locations.slice!(skip_locations)

          filtered_locations.map.with_index do |location, index|
            {
              id: index,
              text: location.to_s.encode('UTF-8'),
              file: (location.absolute_path || location.path)&.encode('UTF-8'),
              line: location.lineno,
              function: location.label&.encode('UTF-8')
            }
          end
        end
      end
    end
  end
end
