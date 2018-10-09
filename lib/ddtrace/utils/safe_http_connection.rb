require 'net/http'
require 'timeout'

require 'ddtrace/utils/circuit_breaker'

module Datadog
  module Utils
    # Safe persistent http connection
    class SafeHttpConnection
      attr_reader :hostname, :port

      def initialize(hostname, port = nil, max_failures = 5, retry_after = 5000)
        @hostname = hostname
        @port = port
        @open_timeout = 0.5 # second
        @read_timeout = 2 # second
        @timeout = 2 # general timeout (seconds)
        @connection = nil
        @circuit_breaker = CircuitBreaker.new(max_failures, retry_after)
        @mutex = Mutex.new
      end

      def connection
        @connection ||= begin
          Net::HTTP.new(@hostname, @port).tap do |connection|
            connection.open_timeout = @open_timeout
            connection.read_timeout = @read_timeout
          end
        end
      end

      def send_request(request)
        @circuit_breaker.with do
          do_send_request(request)
        end
      end

      def close
        connection.finish if connection.started?
      end

      private

      def do_send_request(request)
        connection.start unless connection.started?

        Timeout.timeout(@timeout) do
          connection.request(request)
        end
      rescue StandardError => ex
        safe_connection_finish
        Datadog::Tracer.log.error("cannot send request: #{ex}")
        raise ex
      end

      def safe_connection_finish
        connection.finish  if connection.started?
      rescue StandardError => ex
        Datadog::Tracer.log.error("cannot finish connection: #{ex}")
      end
    end
  end
end
