# typed: true
require 'ddtrace/transport/io/client'
require 'datadog/profiling/transport/client'
require 'datadog/profiling/transport/request'
require 'datadog/profiling/transport/io/response'

module Datadog
  module Profiling
    module Transport
      module IO
        # IO transport for profiling
        class Client < Datadog::Transport::IO::Client
          include Transport::Client

          def send_profiling_flush(flush)
            # Build a request
            request = Profiling::Transport::Request.new(flush)
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
