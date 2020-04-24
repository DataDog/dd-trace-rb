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

      # Concatenates a list of elements previously encoded by +#encode+.
      def join(encoded_elements)
        raise NotImplementedError
      end

      # Serializes a single trace into a String suitable for network transmission.
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

      def join(encoded_data)
        "[#{encoded_data.join(',')}]"
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
                ENCODED_IDS.each do |id|
                  span[id] = span[id].to_s(16) if span.key?(id)
                end
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

      def join(encoded_data)
        packer = MessagePack::Packer.new
        packer.write_array_header(encoded_data.size)

        (packer.to_a + encoded_data).join
      end
    end
  end
end
