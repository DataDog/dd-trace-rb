# typed: true

module Datadog
  module Core
    module Telemetry
      module Http
        module Adapters
          class Net
            attr_reader \
              :uri,
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

            def open(&block)
              # DEV Initializing +Net::HTTP+ directly help us avoid expensive
              # options processing done in +Net::HTTP.start+:
              # https://github.com/ruby/ruby/blob/b2d96abb42abbe2e01f010ffc9ac51f0f9a50002/lib/net/http.rb#L614-L618
              req = ::Net::HTTP.new(@hostname, @port)

              req.use_ssl = @ssl
              req.open_timeout = req.read_timeout = @timeout

              req.start(&block)
            end

            def post(path:, headers:, body:)
              post = ::Net::HTTP::Post.new(path, headers)
              post.body = body

              http_response = open do |http|
                http.request(post)
              end
              puts http_response
              puts http_response.body
              Response.new(http_response)
            rescue StandardError => e
              puts(e)
              InternalErrorResponse.new(e)
            end

            class Response
              attr_reader :http_response

              def initialize(http_response)
                @http_response = http_response
              end

              def payload
                return nil if @http_response.nil?

                @http_response.body
              end

              def code
                return nil if @http_response.nil?

                @http_response.code.to_i
              end

              def ok?
                return nil if @http_response.nil?

                code.between?(200, 299)
              end

              def unsupported?
                return nil if @http_response.nil?

                code == 415
              end

              def not_found?
                return nil if @http_response.nil?

                code == 404
              end

              def client_error?
                return nil if @http_response.nil?

                code.between?(400, 499)
              end

              def server_error?
                return nil if @http_response.nil?

                code.between?(500, 599)
              end

              def inspect
                "#{self.class} ok?:#{ok?} unsupported?:#{unsupported?}, " \
                "not_found?:#{not_found?}, client_error?:#{client_error?}, " \
                "server_error?:#{server_error?}, internal_error?:#{internal_error?}, " \
                "payload:#{payload}, http_response:#{@http_response}"
              end
            end

            class InternalErrorResponse
              attr_reader :error

              def initialize(error)
                @error = error
              end

              def internal_error?
                true
              end

              def inspect
                "internal_error?:#{internal_error?}, error_type:#{@error.class} error:#{@error}"
              end
            end
          end
        end
      end
    end
  end
end
