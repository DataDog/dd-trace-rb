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
            # Only add DSM headers if data streams monitoring is enabled
            if Datadog.configuration.tracing.data_streams.enabled
              processor = Datadog.configuration.tracing.data_streams.processor

              # Create checkpoint for producer (direction:out)
              # We don't create spans here - that happens in event handlers
              processor.set_checkpoint(['direction:out', 'type:kafka'], Time.now.to_f)

              # Add pathway context to message headers using the codec
              message[:headers] ||= {}
              current_context = processor.get_current_pathway
              DataStreams::PathwayCodec.encode(current_context, message[:headers])
            end

            message
          end
        end
      end
    end
  end
end
