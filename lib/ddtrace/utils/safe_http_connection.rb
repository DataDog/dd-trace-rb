require 'net/http'
require 'timeout'

module Datadog
  module Utils
    # Safe persistent http connection
    class SafeHttpConnection
      def initialize(address, port = nil)
        @address = address
        @port = port
        @open_timeout = 0.5 # second
        @read_timeout = 1 # second
        @timeout = 2 # general timeout (seconds)
        @connection = nil
      end

      def connection
        @connection ||= begin
          Net::HTTP.new(@address, @port).tap do |connection|
            connection.open_timeout = @open_timeout
            connection.read_timeout = @read_timeout
          end
        end
      end

      def send_request(request)
        connection.start unless connection.started?

        Timeout.timeout(@timeout) do
          connection.request(request)
        end
      rescue StandardError => ex
        safe_connection_finish
        Datadog::Tracer.log.error("cannot send request: #{ex}")
        raise ex
      end

      def close
        connection.finish if connection.started?
      end

      private

      def safe_connection_finish
        connection.finish  if connection.started?
      rescue StandardError => ex
        Datadog::Tracer.log.error("cannot finish connection: #{ex}")
      end
    end
  end
end
