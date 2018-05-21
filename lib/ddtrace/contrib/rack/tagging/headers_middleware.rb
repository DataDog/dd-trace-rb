require 'ddtrace/utils/tagger'
require 'ddtrace/utils/base_tag_converter'
require 'ddtrace/contrib/rack/tagging/response_tag_converter'
require 'ddtrace/contrib/rack/tagging/request_tag_converter'

module Datadog
  module Contrib
    module Rack
      module Tagging
        # Abstract middleware used for automatically tagging configured headers
        class HeadersMiddleware
          DEFAULT_HEADERS = {
            response: %w[Content-Type X-Request-ID]
          }.freeze

          def initialize(app)
            @app = app
          end

          def call(env)
            span = request_span!(env)
            Datadog::Utils::Tagger.tag(span, request_headers_whitelist, RequestTagConverter.instance, env)
            _, headers, = @app.call(env)
          ensure
            Datadog::Utils::Tagger.tag(span, response_headers_whitelist, ResponseTagger.instance, headers)
          end

          def request_span!(env)
            env[env_request_span] ||= build_request_span(env)
          end

          protected

          def configuration
            raise NotImplementedError
          end

          def build_request_span(_env)
            raise NotImplementedError
          end

          def env_request_span
            raise NotImplementedError
          end

          def tracer
            configuration[:tracer]
          end

          def request_headers_whitelist
            configuration[:headers][:request]
          end

          def response_headers_whitelist
            configuration[:headers][:response]
          end
        end
      end
    end
  end
end
