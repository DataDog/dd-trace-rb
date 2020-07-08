require 'ddtrace/transport/response'

module Datadog
  module Transport
    module IO
      # Response from HTTP transport for traces
      class Response
        include Transport::Response
        include Transport::Traces::Response

        attr_reader \
          :result

        def initialize(result, trace_count = 1)
          @result = result
          @trace_count = trace_count
        end

        def ok?
          true
        end
      end
    end
  end
end
