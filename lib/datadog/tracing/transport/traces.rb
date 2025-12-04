# frozen_string_literal: true

require_relative '../../core/chunker'
require_relative '../../core/transport/parcel'
require_relative '../../core/transport/request'
require_relative '../../core/transport/transport'
require_relative '../../core/utils/array'
require_relative 'http/client'
require_relative 'serializable_trace'
require_relative 'trace_formatter'

module Datadog
  module Tracing
    module Transport
      module Traces
        # Data transfer object for encoded traces
        class EncodedParcel
          include Datadog::Core::Transport::Parcel

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
        class Request < Datadog::Core::Transport::Request
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

          attr_reader :encoder, :max_size, :logger

          #
          # Single traces larger than +max_size+ will be discarded.
          #
          # @param encoder [Datadog::Core::Encoding::Encoder]
          # @param logger [Datadog::Core::Logger]
          # @param max_size [String] maximum acceptable payload size
          def initialize(encoder, logger:, native_events_supported:, max_size: DEFAULT_MAX_PAYLOAD_SIZE)
            @encoder = encoder
            @logger = logger
            @native_events_supported = native_events_supported
            @max_size = max_size
          end

          # Encodes a list of traces in chunks.
          # Before serializing, all traces are normalized. Trace nesting is not changed.
          #
          # @param traces [Enumerable<Trace>] list of traces
          # @return [Enumerable[Array[Bytes,Integer]]] list of encoded chunks: each containing a byte array and
          #   number of traces
          def encode_in_chunks(traces)
            encoded_traces = Core::Utils::Array.filter_map(traces) do |trace|
              encode_one(trace)
            end

            Datadog::Core::Chunker.chunk_by_size(encoded_traces, max_size).map do |chunk|
              [encoder.join(chunk), chunk.size]
            end
          end

          private

          def encode_one(trace)
            encoded = Encoder.encode_trace(
              encoder,
              trace,
              logger: logger,
              native_events_supported: @native_events_supported
            )

            if encoded.size > max_size
              # This single trace is too large, we can't flush it
              logger.debug { "Dropping trace. Payload too large: '#{trace.inspect}'" }
              Datadog.health_metrics.transport_trace_too_large(1)

              return nil
            end

            encoded
          end
        end

        # Encodes traces using {Datadog::Core::Encoding::Encoder} instances.
        module Encoder
          module_function

          def encode_trace(encoder, trace, logger:, native_events_supported:)
            # Format the trace for transport
            TraceFormatter.format!(trace)

            # Make the trace serializable
            serializable_trace = SerializableTrace.new(trace, native_events_supported: native_events_supported)

            # Encode the trace
            encoder.encode(serializable_trace).tap do |encoded|
              # Print the actual serialized trace, since the encoder can change make non-trivial changes
              logger.debug { "Flushing trace: #{encoder.decode(encoded)}" }
            end
          end
        end

        # Sends traces based on transport API configuration.
        #
        # This class initializes the HTTP client, breaks down large
        # batches of traces into smaller chunks and handles
        # API version downgrade handshake.
        class Transport < Core::Transport::Transport
          self.http_client_class = Tracing::Transport::HTTP::Client

          def send_traces(traces)
            encoder = current_api.encoder
            chunker = Datadog::Tracing::Transport::Traces::Chunker.new(
              encoder,
              logger: logger,
              native_events_supported: native_events_supported?
            )

            responses = chunker.encode_in_chunks(traces.lazy).map do |encoded_traces, trace_count|
              request = Request.new(EncodedParcel.new(encoded_traces, trace_count))

              client.send_request(:traces, request).tap do |response|
                if downgrade?(response)
                  downgrade!
                  return send_traces(traces)
                end
              end
            end

            # Force resolution of lazy enumerator.
            #
            # The "correct" method to call here would be `#force`,
            # as this method was created to force the eager loading
            # of a lazy enumerator.
            #
            # Unfortunately, JRuby < 9.2.9.0 erroneously eagerly loads
            # the lazy Enumerator during intermediate steps.
            # This forces us to use `#to_a`, as this method works for both
            # lazy and regular Enumerators.
            # Using `#to_a` can mask the fact that we expect a lazy
            # Enumerator.
            responses = responses.to_a

            Datadog.health_metrics.transport_chunked(responses.size)

            responses
          end

          def stats
            @client.stats
          end

          private

          # Queries the agent for native span events serialization support.
          # This changes how the serialization of span events performed.
          def native_events_supported?
            return @native_events_supported if defined?(@native_events_supported)

            # Check for an explicit override
            option = Datadog.configuration.tracing.native_span_events
            unless option.nil?
              @native_events_supported = option
              return option
            end

            # Otherwise, check for agent support, to ensure a configuration-less setup.
            if (res = Datadog.send(:components).agent_info.fetch)
              @native_events_supported = res.span_events == true
            else
              false
            end
          end
        end
      end
    end
  end
end
