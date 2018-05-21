require 'ddtrace/utils/mass_tagger'
require 'ddtrace/utils/base_tagger'
require 'ddtrace/contrib/rack/tagging/response_tagger'
require 'ddtrace/contrib/rack/tagging/request_tagger'

module Datadog
  module Contrib
    module Rack
      module Tagging
        class HeadersMiddleware
          DEFAULT_HEADERS = {
              response: %w[Content-Type X-Request-ID]
          }.freeze

          def initialize(app)
            @app = app
          end

          def call(env)
            span = request_span!(env)
            Datadog::Utils::MassTagger.tag(span, request_headers_whitelist, RequestTagger.instance, env)
            _, headers, = @app.call(env)
          ensure
            Datadog::Utils::MassTagger.tag(span, response_headers_whitelist, ResponseTagger.instance, headers)
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