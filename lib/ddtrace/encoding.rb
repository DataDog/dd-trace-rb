require 'json'
require 'msgpack'

module Datadog
  # Encoding module that encodes data for the AgentTransport
  module Encoding
    # Encoder interface that provides the logic to encode traces and service
    module Encoder
      def content_type
        raise NotImplementedError
      end

      # Encodes a list of traces, expecting a list of items where each items
      # is a list of spans. Before dump the string in a serialized format all
      # traces are normalized. The traces nesting is not changed.
      def encode_traces(traces)
        to_send = []
        traces.each do |trace|
          to_send << trace.map(&:to_hash)
        end
        encode(to_send)
      end

      # Defines the underlying format used during traces or services encoding.
      # This method must be implemented and should only be used by the internal functions.
      def encode(_)
        raise NotImplementedError
      end
    end

    # Encoder for the JSON format
    module JSONEncoder
      extend Encoder

      CONTENT_TYPE = 'application/json'.freeze

      module_function

      def content_type
        CONTENT_TYPE
      end

      def encode(obj)
        JSON.dump(obj)
      end

      # New version of JSON Encoder that is API compliant.
      module V2
        extend JSONEncoder

        ENCODED_IDS = [
          :trace_id,
          :span_id,
          :parent_id
        ].freeze

        module_function

        def encode_traces(traces)
          trace_hashes = traces.collect do |trace|
            # Convert each trace to hash
            trace.map(&:to_hash).tap do |spans|
              # Convert IDs to hexadecimal
              spans.each do |span|
                ENCODED_IDS.each { |id| span[id] = span[id].to_s(16) }
              end
            end
          end

          # Wrap traces & encode them
          encode(traces: trace_hashes)
        end
      end
    end

    # Encoder for the Msgpack format
    module MsgpackEncoder
      extend Encoder

      module_function

      CONTENT_TYPE = 'application/msgpack'.freeze

      def content_type
        CONTENT_TYPE
      end

      def encode(obj)
        MessagePack.pack(obj)
      end
    end
  end
end
