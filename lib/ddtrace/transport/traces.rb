require 'ddtrace/transport/parcel'
require 'ddtrace/transport/request'
require 'ddtrace/chunker'

module Datadog
  module Transport
    module Traces
      # Data transfer object for encoded traces
      class EncodedParcel
        include Transport::Parcel

        attr_reader :trace_count

        def initialize(data, trace_count)
          super(data)
          @trace_count = trace_count
        end

        def count
          data.length
        end
      end

      # Traces request
      class Request < Transport::Request
      end

      # Traces response
      module Response
        attr_reader :service_rates, :trace_count
      end

      # Traces chunker
      class Chunker
        # Trace agent limit payload size of 10 MiB (since agent v5.11.0):
        # https://github.com/DataDog/datadog-agent/blob/6.14.1/pkg/trace/api/api.go#L46
        #
        # We set the value to a conservative 5 MiB, in case network speed is slow.
        DEFAULT_MAX_PAYLOAD_SIZE = 5 * 1024 * 1024

        attr_reader :encoder, :max_size

        #
        # Single traces larger than +max_size+ will be discarded.
        #
        # @param encoder [Datadog::Encoding::Encoder]
        # @param max_size [String] maximum acceptable payload size
        def initialize(encoder, max_size: DEFAULT_MAX_PAYLOAD_SIZE)
          @encoder = encoder
          @max_size = max_size
        end

        # Encodes a list of traces in chunks.
        # Before serializing, all traces are normalized. Trace nesting is not changed.
        #
        # @param traces [Enumerable<Trace>] list of traces
        # @return [Enumerable[Array[Bytes,Integer]]] list of encoded chunks: each containing a byte array and
        #   number of traces
        def encode_in_chunks(traces)
          encoded_traces = traces.map { |t| encode_one(t) }.reject(&:nil?)

          Datadog::Chunker.chunk_by_size(encoded_traces, max_size).map do |chunk|
            [encoder.join(chunk), chunk.size]
          end
        end

        private

        def encode_one(trace)
          encoded = Encoder.encode_trace(encoder, trace)

          if encoded.size > max_size
            # This single trace is too large, we can't flush it
            Datadog.logger.debug { "Dropping trace. Payload too large: '#{trace.map(&:to_hash)}'" }
            Datadog.health_metrics.transport_trace_too_large(1)

            return nil
          end

          encoded
        end
      end

      # Encodes traces using {Datadog::Encoding::Encoder} instances.
      module Encoder
        module_function

        def encode_trace(encoder, trace)
          encoder.encode(trace.map(&:to_hash))
        end
      end

      # Sends traces based on transport API configuration.
      #
      # This class initializes the HTTP client, breaks down large
      # batches of traces into smaller chunks and handles
      # API version downgrade handshake.
      class Transport
        attr_reader :client, :apis, :default_api, :current_api_id

        def initialize(apis, default_api)
          @apis = apis
          @default_api = default_api

          change_api!(default_api)
        end

        def send_traces(traces)
          encoder = current_api.encoder
          chunker = Datadog::Transport::Traces::Chunker.new(encoder)

          responses = chunker.encode_in_chunks(traces.lazy).map do |encoded_traces, trace_count|
            request = Request.new(EncodedParcel.new(encoded_traces, trace_count))

            client.send_payload(request).tap do |response|
              if downgrade?(response)
                downgrade!
                return send_traces(traces)
              end
            end
          end.force

          Datadog.health_metrics.transport_chunked(responses.size)

          responses
        end

        def stats
          @client.stats
        end

        def current_api
          apis[@current_api_id]
        end

        private

        def downgrade?(response)
          return false unless apis.fallbacks.key?(@current_api_id)
          response.not_found? || response.unsupported?
        end

        def downgrade!
          downgrade_api_id = apis.fallbacks[@current_api_id]
          raise NoDowngradeAvailableError, @current_api_id if downgrade_api_id.nil?
          change_api!(downgrade_api_id)
        end

        def change_api!(api_id)
          raise UnknownApiVersionError, api_id unless apis.key?(api_id)
          @current_api_id = api_id
          @client = HTTP::Client.new(current_api)
        end

        # Raised when configured with an unknown API version
        class UnknownApiVersionError < StandardError
          attr_reader :version

          def initialize(version)
            @version = version
          end

          def message
            "No matching transport API for version #{version}!"
          end
        end

        # Raised when configured with an unknown API version
        class NoDowngradeAvailableError < StandardError
          attr_reader :version

          def initialize(version)
            @version = version
          end

          def message
            "No downgrade from transport API version #{version} is available!"
          end
        end
      end
    end
  end
end
