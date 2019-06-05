require 'ddtrace/transport/response'

module Datadog
  module Transport
    module HTTP
      module Adapters
        # Adapter for Net::HTTP
        class Net
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

          def open
            # Open connection
            ::Net::HTTP.start(hostname, port, open_timeout: timeout, read_timeout: timeout) do |http|
              yield(http)
            end
          end

          def call(env)
            if respond_to?(env.verb)
              send(env.verb, env)
            else
              raise UnknownHTTPMethod, env
            end
          end

          def post(env)
            post = ::Net::HTTP::Post.new(env.path, env[:headers])
            post.body = env.body

            # Connect and send the request
            http_response = open do |http|
              http.request(post)
            end

            # Build and return response
            Response.new(http_response)
          end

          # A wrapped Net::HTTP response that implements the Transport::Response interface
          class Response
            include Datadog::Transport::Response

            attr_reader :http_response

            def initialize(http_response)
              @http_response = http_response
            end

            def payload
              http_response.body
            end

            def code
              return nil if http_response.nil?
              http_response.code.to_i
            end

            def ok?
              return false if http_response.nil?
              code.between?(200, 299)
            end

            def unsupported?
              return false if http_response.nil?
              code == 415
            end

            def not_found?
              return false if http_response.nil?
              code == 404
            end

            def client_error?
              return false if http_response.nil?
              code.between?(400, 499)
            end

            def server_error?
              return false if http_response.nil?
              code.between?(500, 599)
            end
          end
        end
      end
    end
  end
end
