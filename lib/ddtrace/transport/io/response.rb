require 'ddtrace/transport/response'

module Datadog
  module Transport
    module IO
      # Response from HTTP transport for traces
      class Response
        include Transport::Response

        attr_reader \
          :bytes_written

        def initialize(bytes_written)
          @bytes_written = bytes_written
        end

        def ok?
          true
        end
      end
    end
  end
end
