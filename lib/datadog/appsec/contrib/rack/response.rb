module Datadog
  module AppSec
    module Contrib
      module Rack
        # Normalized extration of data from Rack::Response
        module Response
          def self.headers(response)
            response.headers.each_with_object({}) { |(k, v), h| h[k.downcase] = v }
          end

          def self.cookies(response)
            response.cookies
          end

          def self.status(response)
            response.status
          end
        end
      end
    end
  end
end
