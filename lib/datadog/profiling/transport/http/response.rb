# typed: true

require_relative '../../../../ddtrace/transport/http/response'

module Datadog
  module Profiling
    module Transport
      # HTTP transport behavior for profiling
      module HTTP
        # Response from HTTP transport for profiling
        class Response
          include Datadog::Transport::HTTP::Response

          def initialize(http_response, options = {})
            super(http_response)
          end
        end
      end
    end
  end
end
