# frozen_string_literal: true

require_relative '../../transport/traces'
require_relative '../../../core/transport/parcel'
require_relative 'response'
require_relative 'client'

module Datadog
  module Tracing
    module Transport
      module IO
        # IO transport behavior for traces
        module Traces
          # Response from HTTP transport for traces
          class Response < IO::Response
            include Transport::Traces::Response

            def initialize(result, trace_count = 1)
              super(result)
              @trace_count = trace_count
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
            def encode_traces(traces)
              trace_hashes = traces.map do |trace|
                encode_trace(trace)
              end

              # Wrap traces
              {traces: trace_hashes}
            end

            private

            def encode_trace(trace)
              # Convert each trace to hash
              trace.spans.map(&:to_hash).tap do |spans|
                # Convert IDs to hexadecimal
                spans.each do |span|
                  ENCODED_IDS.each do |id|
                    span[id] = span[id].to_s(16) if span.key?(id)
                  end
                end
              end
            end
          end

          # Extensions for HTTP client
          module Client
            include Encoder

            def send_traces(traces)
              # Build a request
              encoded_traces = encode_traces(traces)
              encoder = Core::Encoding::JSONEncoder
              parcel = Core::Transport::Parcel.new(
                encoder.encode(encoded_traces),
                content_type: encoder.content_type,
              )
              req = Transport::Traces::Request.new(parcel)

              [send_request(req) do |out, request|
                # Get already-encoded data from parcel
                data = request.parcel.data

                # Write to IO
                result = if block_given?
                  yield(out, data)
                else
                  write_data(out, data)
                end

                # Generate response
                Traces::Response.new(result)
              end]
            end
          end

          # Add traces behavior to transport components
          IO::Client.include(Traces::Client)
        end
      end
    end
  end
end
