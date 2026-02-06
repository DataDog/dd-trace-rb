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
          SAMPLE_BODY_KEY = :__datadog_appsec_sample_downstream_body

          def call(env)
            context = AppSec.active_context
            return @app.call(env) unless context && AppSec.rasp_enabled?

            url = env.url.to_s
            headers = normalize_headers(env.request_headers)
            # @type var ephemeral_data: ::Datadog::AppSec::Context::input_data
            ephemeral_data = {
              'server.io.net.url' => url,
              'server.io.net.request.method' => env.method.to_s.upcase,
              'server.io.net.request.headers' => headers
            }

            is_redirect = context.state[:downstream_redirect_url] == url

            if is_redirect
              context.state.delete(:downstream_redirect_url)
              env[SAMPLE_BODY_KEY] = true
            else
              mark_body_sampling!(env, context: context)
            end

            if !is_redirect && env[SAMPLE_BODY_KEY]
              body = parse_body(env.body, content_type: headers['content-type'])
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
            # @type var ephemeral_data: ::Datadog::AppSec::Context::input_data
            ephemeral_data = {
              'server.io.net.response.status' => env.status.to_s,
              'server.io.net.response.headers' => headers
            }

            is_redirect = (300...400).cover?(env.status) && headers.key?('location')
            if is_redirect && env[SAMPLE_BODY_KEY]
              context.state[:downstream_redirect_url] = URI.join(env.url.to_s, headers['location']).to_s
            end

            if !is_redirect && env[SAMPLE_BODY_KEY]
              body = parse_body(env.body, content_type: headers['content-type'])
              ephemeral_data['server.io.net.response.body'] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_RESPONSE_PHASE)
            handle(result, context: context) if result.match?
          end

          def mark_body_sampling!(env, context:)
            max = Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests
            return if context.state[:downstream_body_analyzed_count] >= max
            return unless context.downstream_body_sampler.sample?

            context.state[:downstream_body_analyzed_count] += 1
            env[SAMPLE_BODY_KEY] = true
          end

          def parse_body(body, content_type:)
            media_type = Utils::HTTP::MediaType.parse(content_type)
            return unless media_type

            Utils::HTTP::Body.parse(body, media_type: media_type)
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
