# typed: true

module Datadog
  module Core
    module Telemetry
      module Http
        class Env
          def verb
            @verb
          end

          def verb=(value)
            @verb = value
          end

          def path
            @path
          end

          def path=(value)
            @path = value
          end

          def body
            @body
          end

          def body=(value)
            @body = value
          end

          def headers
            @headers ||= {}
          end

          def headers=(value)
            @headers = value
          end

          def timeout
            @timeout
          end

          def timeout=(value)
            @timeout = value
          end

          def ssl
            @ssl
          end

          def ssl=(value)
            @ssl = value
          end
        end
      end
    end
  end
end
