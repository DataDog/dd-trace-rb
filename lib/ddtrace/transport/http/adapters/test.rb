require 'ddtrace/transport/response'

module Datadog
  module Transport
    module HTTP
      module Adapters
        # Adapter for testing
        class Test
          attr_reader \
            :buffer,
            :status

          def initialize(buffer = nil)
            @buffer = buffer
            @mutex = Mutex.new
            @status = 200
          end

          def call(env)
            add_request(env)
            Response.new(status)
          end

          def buffer?
            !@buffer.nil?
          end

          def add_request(env)
            @mutex.synchronize { buffer << env } if buffer?
          end

          def set_status!(status)
            @status = status
          end

          # Response for test adapter
          class Response
            include Datadog::Transport::Response

            attr_reader \
              :body,
              :code

            def initialize(code, body = nil)
              @code = code
              @body = body
            end

            def payload
              @body
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

            def inspect
              "#{super}, code:#{code}"
            end
          end
        end
      end
    end
  end
end
