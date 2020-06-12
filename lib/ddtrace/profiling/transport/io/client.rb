require 'ddtrace/transport/io/client'
require 'ddtrace/profiling/transport/request'
require 'ddtrace/profiling/transport/io/response'

module Datadog
  module Profiling
    module Transport
      module IO
        # Profiling extensions for IO client
        class Client < Datadog::Transport::IO::Client
          def send_flushes(flushes)
            # Build a request
            request = Profiling::Transport::Request.new(flushes)
            send_request(request)
          end

          def build_response(_request, _data, result)
            Profiling::Transport::IO::Response.new(result)
          end
        end
      end
    end
  end
end
