# typed: true

module Datadog
  module Core
    module Telemetry
      module Http
        # Data structure for an HTTP request
        class Env
          attr_accessor :verb, :path, :body, :timeout, :ssl

          attr_writer :headers

          def headers
            @headers ||= {}
          end
        end
      end
    end
  end
end
