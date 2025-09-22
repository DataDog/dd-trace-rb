# frozen_string_literal: true

require_relative 'ext'
require_relative '../../data_streams/pathway_codec'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Middleware for WaterDrop that adds DSM pathway context to message headers
        # This runs BEFORE validation, so headers are always present
        class Middleware
          def call(message)
            puts "🔍 [WATERDROP MIDDLEWARE] Processing message: topic=#{message[:topic]}"

            # Only add DSM headers if data streams monitoring is enabled
            if Datadog.configuration.tracing.data_streams.enabled
              puts "🔍 [WATERDROP MIDDLEWARE] DSM is enabled, creating checkpoint"
              processor = Datadog.configuration.tracing.data_streams.processor

              # Create checkpoint for producer (direction:out)
              # We don't create spans here - that happens in event handlers
              topic = message[:topic] || 'unknown'
              tags = ["topic:#{topic}", 'direction:out', 'type:kafka']
              puts "🔍 [WATERDROP MIDDLEWARE] Creating DSM checkpoint with tags: #{tags}"

              checkpoint = processor.set_checkpoint(tags, Time.now.to_f)
              puts "🔍 [WATERDROP MIDDLEWARE] DSM checkpoint created: #{checkpoint ? 'YES' : 'NO'}"

              # Add pathway context to message headers using the codec
              message[:headers] ||= {}
              current_context = processor.get_current_pathway
              DataStreams::PathwayCodec.encode(current_context, message[:headers])
              puts "🔍 [WATERDROP MIDDLEWARE] Added pathway context to headers"
            else
              puts "🔍 [WATERDROP MIDDLEWARE] DSM is disabled"
            end

            message
          end
        end
      end
    end
  end
end
