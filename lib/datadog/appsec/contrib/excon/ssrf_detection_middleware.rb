# frozen_string_literal: true

require 'excon'

require_relative '../../event'
require_relative '../../trace_keeper'
require_relative '../../security_event'

module Datadog
  module AppSec
    module Contrib
      module Excon
        # AppSec Middleware for Excon
        class SSRFDetectionMiddleware < ::Excon::Middleware::Base
          def request_call(data)
            context = AppSec.active_context
            return super unless context && AppSec.rasp_enabled?

            headers = normalize_headers(data[:headers])
            ephemeral_data = {
              'server.io.net.url' => request_url(data),
              'server.io.net.request.method' => data[:method].to_s.upcase,
              'server.io.net.request.headers' => headers
            }

            if Utils::HTTP::MediaType.json?(headers['content-type'])
              body = parse_body(data[:body])
              ephemeral_data['server.io.net.request.body'] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_REQUEST_PHASE)
            handle(result, context: context) if result.match?

            super
          end

          def response_call(data)
            context = AppSec.active_context
            return super unless context && AppSec.rasp_enabled?

            headers = normalize_headers(data.dig(:response, :headers))
            ephemeral_data = {
              'server.io.net.response.status' => data.dig(:response, :status).to_s,
              'server.io.net.response.headers' => headers
            }

            if Utils::HTTP::MediaType.json?(headers['content-type'])
              body = parse_body(data.dig(:response, :body))
              ephemeral_data['server.io.net.response.body'] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_RESPONSE_PHASE)
            handle(result, context: context) if result.match?

            super
          end

          private

          def request_url(data)
            klass = (data[:scheme] == 'https') ? URI::HTTPS : URI::HTTP
            klass.build(host: data[:host], path: data[:path], query: data[:query]).to_s
          end

          def normalize_headers(headers)
            return {} if headers.nil? || headers.empty?

            headers.each_with_object({}) do |(key, value), memo|
              memo[key.downcase] = value.is_a?(Array) ? value.join(', ') : value
            end
          end

          def parse_body(body)
            return if body.nil?

            body.rewind if body.respond_to?(:rewind)
            content = body.respond_to?(:read) ? body.read : body
            body.rewind if body.respond_to?(:rewind)

            return if content.empty?

            JSON.parse(content)
          rescue => e
            AppSec.telemetry.report(e, description: 'AppSec: Failed to parse JSON body')

            nil
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
