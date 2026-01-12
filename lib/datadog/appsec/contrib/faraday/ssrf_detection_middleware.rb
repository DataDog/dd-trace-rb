# frozen_string_literal: true

require_relative '../../event'
require_relative '../../trace_keeper'
require_relative '../../security_event'

module Datadog
  module AppSec
    module Contrib
      module Faraday
        # AppSec SSRF detection Middleware for Faraday
        class SSRFDetectionMiddleware < ::Faraday::Middleware
          def call(env)
            context = AppSec.active_context
            return @app.call(env) unless context && AppSec.rasp_enabled?

            timeout = Datadog.configuration.appsec.waf_timeout
            ephemeral_data = {
              'server.io.net.url' => env.url.to_s,
              'server.io.net.request.method' => env.method.to_s.upcase,
              'server.io.net.request.headers' => env.request_headers.transform_keys(&:downcase)
            }

            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_REQUEST_PHASE)
            handle(result) if result.match?

            response = @app.call(env)

            ephemeral_data = {
              'server.io.net.response.status' => response.status.to_s,
              'server.io.net.response.headers' => response.headers.transform_keys(&:downcase)
            }
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_RESPONSE_PHASE)
            handle(result) if result.match?

            response
          end

          private

          def handle(result)
            context = AppSec.active_context

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
