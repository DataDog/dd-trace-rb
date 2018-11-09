require 'ddtrace/transport/http/fallbacks'

module Datadog
  module Transport
    module HTTP
      # A hash mapping of API version => Transport::HTTP::API
      class APIMap < Hash
        include Fallbacks
      end
    end
  end
end
