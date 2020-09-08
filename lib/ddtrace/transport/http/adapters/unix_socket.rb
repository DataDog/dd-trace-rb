require 'net/http'
require 'ddtrace/transport/http/adapters/net'

module Datadog
  module Transport
    module HTTP
      module Adapters
        # Adapter for Unix sockets
        class UnixSocket < Adapters::Net
          DEFAULT_TIMEOUT = 1

          attr_reader \
            :filepath,
            :timeout

          def initialize(filepath, options = {})
            @filepath = filepath
            @timeout = options.fetch(:timeout, DEFAULT_TIMEOUT)
          end

          def open
            # Open connection
            connection = HTTP.new(
              filepath,
              read_timeout: timeout,
              continue_timeout: timeout
            )

            connection.start do |http|
              yield(http)
            end
          end

          def url
            "http+unix://#{filepath}?timeout=#{timeout}"
          end

          # Re-implements Net:HTTP with underlying Unix socket
          class HTTP < ::Net::HTTP
            DEFAULT_TIMEOUT = 1

            attr_reader \
              :filepath,
              :unix_socket

            def initialize(filepath, options = {})
              super('localhost', 80)
              @filepath = filepath
              @read_timeout = options.fetch(:read_timeout, DEFAULT_TIMEOUT)
              @continue_timeout = options.fetch(:continue_timeout, DEFAULT_TIMEOUT)
              @debug_output = options[:debug_output] if options.key?(:debug_output)
            end

            def connect
              @unix_socket = UNIXSocket.open(filepath)
              @socket = ::Net::BufferedIO.new(@unix_socket).tap do |socket|
                socket.read_timeout = @read_timeout
                socket.continue_timeout = @continue_timeout
                socket.debug_output = @debug_output
              end
              on_connect
            end
          end
        end
      end
    end
  end
end
