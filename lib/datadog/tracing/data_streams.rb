module Datadog
  module Tracing
    module DataStreams
      module DataStreamsProcessor
        def self.set_checkpoint(checkpoint, payload_size: 0)
        end
      end

      module DsmPathwayCodec
        def self.encode(ctx, headers)
        end

        def self.decode(headers, processor)
        end
      end
    end
  end
end