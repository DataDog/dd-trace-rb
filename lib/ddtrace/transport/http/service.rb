require 'net/http'

module Datadog
  module Transport
    module HTTP
      # An HTTP service which tracer data can be sent to.
      # Opens and manages connections.
      class Service
        attr_reader \
          :hostname,
          :port,
          :timeout

        DEFAULT_TIMEOUT = 1

        def initialize(hostname, port, options = {})
          @hostname = hostname
          @port = port
          @timeout = options[:timeout] || DEFAULT_TIMEOUT
        end

        def open(options = {})
          # Open connection
          Net::HTTP.start(hostname, port, open_timeout: timeout, read_timeout: timeout) do |http|
            yield(http)
          end
        end
      end
    end
  end
end
