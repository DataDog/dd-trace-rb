# frozen_string_literal: true

module Datadog
  module Tracing
    module DataStreams
      # DsmPathwayCodec is responsible for:
      #   - encoding and injecting DSM pathway context into produced message headers
      #   - extracting and decoding DSM pathway context from consumed message headers
      class PathwayCodec
        PROPAGATION_KEY = 'dd-pathway-ctx'
        PROPAGATION_KEY_BASE64 = 'dd-pathway-ctx-base64'

        # Encode pathway context into carrier (headers)
        # @param [PathwayContext] ctx The pathway context to encode
        # @param [Hash] carrier The headers hash to inject into
        def self.encode(ctx, carrier)
          return unless ctx&.hash

          carrier[PROPAGATION_KEY_BASE64] = ctx.encode_b64
        end

        # Decode pathway context from carrier (headers)
        # @param [Hash] carrier The headers hash to extract from
        # @param [Processor] processor The DSM processor instance
        # @return [PathwayContext, nil] The decoded pathway context or nil
        def self.decode(carrier, processor)
          return nil unless carrier

          if carrier.key?(PROPAGATION_KEY_BASE64)
            # Decode V2 base64 encoding
            processor.decode_pathway_b64(carrier[PROPAGATION_KEY_BASE64])
          elsif carrier.key?(PROPAGATION_KEY)
            # Decode V1 encoding (legacy support)
            processor.decode_pathway(carrier[PROPAGATION_KEY])
          end
        end
      end
    end
  end
end

