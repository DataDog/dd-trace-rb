module Datadog
  module AppSec
    module Contrib
      module Rack
        # Normalized extration of data from Rack::Request
        module Request
          def self.query(request)
            request.query_string.split('&').map { |e| e.split('=').map { |s| CGI.unescape(s) } }
          end

          def self.headers(request)
            request.each_header.each_with_object({}) do |(k, v), h|
              h[k.gsub(/^HTTP_/, '').downcase.tr('_', '-')] = v if k =~ /^HTTP_/
            end
          end

          def self.body(request)
            request.body.read.tap { request.body.rewind }
          end

          def self.url(request)
            request.url
          end

          def self.cookies(request)
            request.cookies
          end
        end
      end
    end
  end
end
