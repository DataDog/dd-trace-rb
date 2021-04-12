require 'ddtrace/transport/http/response'
require 'ddtrace/profiling/transport/response'

module Datadog
  module Profiling
    module Transport
      # HTTP transport behavior for profiling
      module HTTP
        # Response from HTTP transport for profiling
        class Response
          include Datadog::Transport::HTTP::Response
          include Profiling::Transport::Response

          def initialize(http_response, options = {})
            super(http_response)
          end
        end
      end
    end
  end
end
