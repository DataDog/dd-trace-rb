# typed: true

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Normalized extration of data from Rack::Request
        module Request
          def self.query(request)
            request.query_string.split('&').map { |e| e.split('=').map { |s| CGI.unescape(s) } }
          end

          # Rack < 2.0 does not have :each_header
          # TODO: We need access to Rack here. We must make sure we are able to load AppSec without Rack,
          # TODO: while still ensure correctness in ths code path.
          if defined?(::Rack) && ::Rack::Request.instance_methods.include?(:each_header)
            def self.headers(request)
              request.each_header.each_with_object({}) do |(k, v), h|
                h[k.gsub(/^HTTP_/, '').downcase.tr('_', '-')] = v if k =~ /^HTTP_/
              end
            end
          else
            def self.headers(request)
              request.env.each_with_object({}) do |(k, v), h|
                h[k.gsub(/^HTTP_/, '').downcase.tr('_', '-')] = v if k =~ /^HTTP_/
              end
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
