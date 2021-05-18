require 'ddtrace/transport/response'
require 'ethon'

module Datadog
  module Transport
    module HTTP
      module Adapters
        # Adapter for Ethon >= 0.8.0.
        # More memory efficient than Net::HTTP.
        class Ethon
          attr_reader \
            :hostname,
            :port,
            :timeout

          DEFAULT_TIMEOUT = 10

          def initialize(
            hostname = Datadog::Transport::HTTP.default_hostname,
            port = Datadog::Transport::HTTP.default_port,
            options = {}
          )
            @hostname = hostname
            @port = port
            @timeout = options[:timeout] || DEFAULT_TIMEOUT

            @uri = URI::HTTP.build(host: hostname, port: port).to_s
          end

          def call(env)
            if respond_to?(env.verb)
              send(env.verb, env)
            else
              raise UnknownHTTPMethod, env
            end
          end

          def post(env)
            client = ::Ethon::Easy.new

            post = ::Ethon::Easy::Http::Post.new(@uri + env.path, headers: env.headers, body: env.body)
            post.setup(client)

            client.perform

            Response.new(client.response_code, client.response_body)
          end

          def url
            "http://#{hostname}:#{port}?timeout=#{timeout}"
          end

          # Raised when called with an unknown HTTP method
          class UnknownHTTPMethod < StandardError
            attr_reader :verb

            def initialize(verb)
              super("No matching Net::HTTP function for '#{verb}'!")
              @verb = verb
            end
          end

          # A wrapped Net::HTTP response that implements the Transport::Response interface
          class Response
            include Datadog::Transport::Response

            attr_reader :code, :payload

            def initialize(code, payload)
              @code = code
              @payload = payload
            end

            def ok?
              code.between?(200, 299)
            end

            def unsupported?
              code == 415
            end

            def not_found?
              code == 404
            end

            def client_error?
              code.between?(400, 499)
            end

            def server_error?
              code.between?(500, 599)
            end
          end
        end
      end
    end
  end
end
