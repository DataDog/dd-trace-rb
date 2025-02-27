# frozen_string_literal: true

module Datadog
  module AppSec
    module ActionsHandler
      # Module that collects the stack trace into formatted hash
      module StackTraceCollection
        module_function

        def collect(max_depth:, top_percent:)
          locations = (caller_locations || []).reject { |location| location.to_s.include?('lib/datadog') }

          return [] if locations.empty?
          return StackTraceCollection.convert(locations) if max_depth.zero? || locations.size <= max_depth

          top_limit = (max_depth * top_percent / 100.0).round
          bottom_limit = locations.size - (max_depth - top_limit)

          locations.slice!(top_limit...bottom_limit)
          StackTraceCollection.convert(locations)
        end

        def convert(locations)
          locations.map.with_index do |location, index|
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
