# rubocop:disable Naming/FileName
# frozen_string_literal: true

require 'excon'

module Datadog
  module AppSec
    module Contrib
      module Excon
        # AppSec Middleware for Excon
        class SSRFDetectionMiddleware < ::Excon::Middleware::Base
          def request_call(data)
            return super unless AppSec.rasp_enabled? && AppSec.active_context

            context = AppSec.active_context

            request_url = URI.join("#{data[:scheme]}://#{data[:host]}", data[:path]).to_s
            ephemeral_data = { 'server.io.net.url' => request_url }

            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, Datadog.configuration.appsec.waf_timeout)

            if result.match?
              Datadog::AppSec::Event.tag_and_keep!(context, result)

              context.events << {
                waf_result: result,
                trace: context.trace,
                span: context.span,
                request_url: request_url,
                actions: result.actions
              }

              ActionsHandler.handle(result.actions)
            end

            super
          end
        end
      end
    end
  end
end
# rubocop:enable Naming/FileName
