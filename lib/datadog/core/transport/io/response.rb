# typed: true
require 'datadog/core/transport/response'

module Datadog
  module Core
    module Transport
      module IO
        # Response from HTTP transport for traces
        class Response
          include Transport::Response

          attr_reader \
            :result

          def initialize(result)
            @result = result
          end

          def ok?
            true
          end
        end
      end
    end
  end
end
