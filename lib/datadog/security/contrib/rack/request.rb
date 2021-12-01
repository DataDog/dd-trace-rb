module Datadog
  module Security
    module Contrib
      module Rack
        module Request
          def self.query(request)
            request.query_string.split('&').map { |e| e.split('=').map { |s| CGI.unescape(s) } }
          end

          def self.headers(request)
            request.each_header.each_with_object({}) { |(k, v), h| h[k.gsub(/^HTTP_/, '').downcase.gsub('_', '-')] = v if k =~ /^HTTP_/ }
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
