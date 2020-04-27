require 'ddtrace/transport/traces'

require 'ddtrace/transport/io/response'
require 'ddtrace/transport/io/client'

module Datadog
  module Transport
    module IO
      # IO transport behavior for traces
      module Traces
        # Response from HTTP transport for traces
        class Response < IO::Response
          include Transport::Traces::Response
        end

        # Extensions for HTTP client
        module Client
          def send_traces(traces)
            # Build a request
            req = Transport::Traces::Request.new(traces, traces.count)

            [send_request(req) do |out, request|
              # Encode trace data
              data = encode_data(encoder, request.parcel.data)

              # Write to IO
              result = if block_given?
                         yield(out, data)
                       else
                         write_data(out, data)
                       end

              # Generate response
              Traces::Response.new(result, 1)
            end]
          end
        end

        # Encoder for IO-specific trace encoding
        # API compliant when used with {JSONEncoder}.
        module Encoder
          ENCODED_IDS = [
            :trace_id,
            :span_id,
            :parent_id
          ].freeze

          # Encodes a list of traces
          def encode_data(encoder, traces)
            trace_hashes = traces.map do |trace|
              encode_trace(trace)
            end

            # Wrap traces & encode them
            encoder.encode(traces: trace_hashes)
          end

          private

          def encode_trace(trace)
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
        end

        # Add traces behavior to transport components
        IO::Client.send(:include, Traces::Client)
        IO::Client.send(:include, Traces::Encoder)
      end
    end
  end
end
