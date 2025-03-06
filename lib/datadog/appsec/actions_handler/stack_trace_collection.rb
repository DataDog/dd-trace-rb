# frozen_string_literal: true

module Datadog
  module AppSec
    module ActionsHandler
      # Module that collects the stack trace into formatted hash
      module StackTraceCollection
        module_function

        def collect(max_depth:, top_percent:)
          locations = StackTraceCollection.filter_map_datadog_locations(caller_locations || [])

          return [] if locations.empty?
          return StackTraceCollection.convert(locations) if max_depth.zero? || locations.size <= max_depth

          top_limit = (max_depth * top_percent / 100.0).round
          bottom_limit = locations.size - (max_depth - top_limit)

          locations.slice!(top_limit...bottom_limit)
          StackTraceCollection.convert(locations)
        end

        def filter_map_datadog_locations(locations)
          locations.each_with_object([]) do |location, result|
            text = location.to_s
            next if text.include?('lib/datadog')

            result << {
              text: text,
              file: location.absolute_path || location.path,
              line: location.lineno,
              function: location.label
            }
          end
        end

        def convert(locations)
          locations.each_with_index do |location, index|
            location[:id] = index
            # Strings can be frozen so we need to copy them
            location[:text] = location[:text].encode('UTF-8')
            location[:file] = location[:file]&.encode('UTF-8')
            location[:function] = location[:function]&.encode('UTF-8')
          end
        end
      end
    end
  end
end
