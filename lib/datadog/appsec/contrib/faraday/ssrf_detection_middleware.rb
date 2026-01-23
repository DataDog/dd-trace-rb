# frozen_string_literal: true

require_relative '../../event'
require_relative '../../trace_keeper'
require_relative '../../security_event'
require_relative '../../utils/http/media_type'
require_relative '../../utils/http/body'

module Datadog
  module AppSec
    module Contrib
      module Faraday
        # AppSec SSRF detection Middleware for Faraday
        class SSRFDetectionMiddleware < ::Faraday::Middleware
          def call(env)
            context = AppSec.active_context
            return @app.call(env) unless context && AppSec.rasp_enabled?

            headers = normalize_headers(env.request_headers)
            ephemeral_data = {
              'server.io.net.url' => env.url.to_s,
              'server.io.net.request.method' => env.method.to_s.upcase,
              'server.io.net.request.headers' => headers
            }

            if (media_type = Utils::HTTP::MediaType.parse(headers['content-type']))
              body = Utils::HTTP::Body.parse(env.body, media_type: media_type)
              ephemeral_data['server.io.net.request.body'] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_REQUEST_PHASE)
            handle(result, context: context) if result.match?

            @app.call(env).on_complete { |response_env| on_complete(response_env, context: context) }
          end

          private

          def on_complete(env, context:)
            headers = normalize_headers(env.response_headers)
            ephemeral_data = {
              'server.io.net.response.status' => env.status.to_s,
              'server.io.net.response.headers' => headers
            }

            if (media_type = Utils::HTTP::MediaType.parse(headers['content-type']))
              body = Utils::HTTP::Body.parse(env.body, media_type: media_type)
              ephemeral_data['server.io.net.response.body'] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_RESPONSE_PHASE)
            handle(result, context: context) if result.match?
          end

          def normalize_headers(headers)
            return {} if headers.nil? || headers.empty?

            headers.transform_keys(&:downcase)
          end

          def handle(result, context:)
            AppSec::Event.tag(context, result)
            TraceKeeper.keep!(context.trace) if result.keep?

            context.events.push(
              AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
            )

            AppSec::ActionsHandler.handle(result.actions)
          end
        end
      end
    end
  end
end
