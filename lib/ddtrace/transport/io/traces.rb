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
            req = Transport::Traces::Request.new(traces)

            send_request(req) do |out, request|
              # Encode trace data
              encoded_data = request.parcel.encode_with(encoder)

              # Write to IO
              bytes_written = out.write(encoded_data)

              # Generate response
              Traces::Response.new(bytes_written)
            end
          end
        end

        # Add traces behavior to transport components
        IO::Client.send(:include, Traces::Client)
      end
    end
  end
end
