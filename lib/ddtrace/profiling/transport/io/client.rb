require 'ddtrace/profiling/transport/request'
require 'ddtrace/profiling/transport/io/response'

module Datadog
  module Profiling
    module Transport
      module IO
        # Profiling extensions for IO client
        module Client
          def send_events(events)
            # Build a request
            req = Profiling::Transport::Request.new(events)

            send_request(req) do |out, request|
              # Encode trace data
              data = encode_data(encoder, request)

              # Write to IO
              result = if block_given?
                         yield(out, data)
                       else
                         write_data(out, data)
                       end

              # Generate response
              Profiling::Transport::IO::Response.new(result)
            end
          end
        end
      end
    end
  end
end
