module Datadog
  module Security
    module Contrib
      module Rack
        module Response
          def self.headers(response)
            response.headers
          end

          def self.cookies(response)
            response.cookies
          end
        end
      end
    end
  end
end
