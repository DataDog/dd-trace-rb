# typed: true

require 'datadog/core/telemetry/http/response'

module Datadog
  module Core
    module Telemetry
      module Http
        module Adapters
          class Net
            attr_reader \
              :hostname,
              :port,
              :timeout,
              :ssl

            DEFAULT_TIMEOUT = 30

            def initialize(hostname:, port: nil, timeout: DEFAULT_TIMEOUT, ssl: true)
              @hostname = hostname
              @port = port
              @timeout = timeout
              @ssl = ssl
            end

            def self.build(agent_settings)
              new(
                hostname: agent_settings.hostname,
                port: agent_settings.port,
                timeout: agent_settings.timeout_seconds,
                ssl: agent_settings.ssl
              )
            end

            def open(&block)
              req = ::Net::HTTP.new(@hostname, @port)

              req.use_ssl = @ssl
              req.open_timeout = req.read_timeout = @timeout

              req.start(&block)
            end

            def post(env)
              post = ::Net::HTTP::Post.new(env.path, env.headers)
              post.body = env.body

              http_response = open do |http|
                http.request(post)
              end

              Response.new(http_response)
            end

            class Response
              include Datadog::Core::Telemetry::Http::Response

              attr_reader :http_response

              def initialize(http_response)
                @http_response = http_response
              end

              def payload
                return super if http_response.nil?

                http_response.body
              end

              def code
                return super if http_response.nil?

                http_response.code.to_i
              end

              def ok?
                return super if http_response.nil?

                code.between?(200, 299)
              end

              def unsupported?
                return super if http_response.nil?

                code == 415
              end

              def not_found?
                return super if http_response.nil?

                code == 404
              end

              def client_error?
                return super if http_response.nil?

                code.between?(400, 499)
              end

              def server_error?
                return super if http_response.nil?

                code.between?(500, 599)
              end

              def inspect
                "#{super}, http_response:#{http_response}"
              end
            end
          end
        end
      end
    end
  end
end
