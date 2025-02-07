# frozen_string_literal: true

require_relative 'frame'

module Datadog
  module AppSec
    module ActionsHandler
      module StackTrace
        # Represent a stack trace with its id and message in message pack
        module Collector
          class << self
            def collect(locations)
              return [] if locations.nil? || locations.empty?

              skip_frames = skip_frames(locations.size)
              frames = []

              locations.each_with_index do |location, index|
                next if skip_frames.include?(index)

                frames << StackTrace::Frame.new(
                  id: index,
                  text: location.to_s.encode('UTF-8'),
                  file: file_path(location),
                  line: location.lineno,
                  function: function_label(location)
                )
              end
              frames
            end

            private

            def skip_frames(locations_size)
              max_depth = Datadog.configuration.appsec.stack_trace.max_depth
              return [] if max_depth == 0 || locations_size <= max_depth

              top_frames_limit = (max_depth * Datadog.configuration.appsec.stack_trace.max_depth_top_percent / 100.0).round
              bottom_frames_limit = locations_size - (max_depth - top_frames_limit)
              (top_frames_limit...bottom_frames_limit)
            end

            def file_path(location)
              path = location.absolute_path || location.path
              return if path.nil?

              path.encode('UTF-8')
            end

            def function_label(location)
              label = location.label
              return if label.nil?

              label.encode('UTF-8')
            end
          end
        end
      end
    end
  end
end
