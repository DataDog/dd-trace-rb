require_relative '../../../tracing/client_ip'
require_relative '../../../tracing/contrib/rack/header_collection'

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Normalized extration of data from Rack::Request
        module Request
          def self.query(request)
            # Downstream libddwaf expects keys and values to be extractable
            # separately so we can't use [[k, v], ...]. We also want to allow
            # duplicate keys, so we use [{k, v}, ...] instead.
            request.query_string.split('&').map do |e|
              k, v = e.split('=').map { |s| CGI.unescape(s) }

              { k => v }
            end
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

          def self.form_hash(request)
            # force form data processing
            request.POST if request.form_data?

            # usually Hash<String,String> but can be a more complex
            # Hash<String,String||Array||Hash> when e.g coming from JSON
            request.env['rack.request.form_hash']
          end

          def self.client_ip(request)
            remote_ip = request.env['REMOTE_ADDR']
            headers = Datadog::Tracing::Contrib::Rack::Header::RequestHeaderCollection.new(request.env)

            result = Datadog::Tracing::ClientIp.raw_ip_from_request(headers, remote_ip)

            if result.raw_ip
              ip = Datadog::Tracing::ClientIp.strip_decorations(result.raw_ip)
              return unless Datadog::Tracing::ClientIp.valid_ip?(ip)

              ip
            end
          end
        end
      end
    end
  end
end
