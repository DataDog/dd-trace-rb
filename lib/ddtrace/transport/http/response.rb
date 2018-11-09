require 'ddtrace/transport/response'

module Datadog
  module Transport
    module HTTP
      # A wrapped HTTP response that implements the Transport::Response interface
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
