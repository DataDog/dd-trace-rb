# typed: false
require 'net/http'
require 'ddtrace/ext/transport'
require 'ddtrace/transport/http/adapters/net'

module Datadog
  module Transport
    module HTTP
      module Adapters
        # Adapter for Unix sockets
        class UnixSocket < Adapters::Net
          attr_reader \
            :filepath,
            :timeout

          # @deprecated Positional parameters are deprecated. Use named parameters instead.
          def initialize(filepath = nil, **options)
            @filepath = filepath || options[:filepath]
            @timeout = options.fetch(:timeout, Ext::Transport::UnixSocket::DEFAULT_TIMEOUT_SECONDS)
          end

          def self.build(agent_settings)
            new(
              filepath: agent_settings.uds_path,
              timeout: agent_settings.timeout_seconds,
            )
          end

          def open(&block)
            # Open connection
            connection = HTTP.new(
              filepath,
              read_timeout: timeout,
              continue_timeout: timeout
            )

            connection.start(&block)
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
