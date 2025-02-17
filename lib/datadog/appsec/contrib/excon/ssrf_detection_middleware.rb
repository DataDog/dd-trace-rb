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
            context = AppSec.active_context

            if context && AppSec.rasp_enabled?
              request_url = data[:host] # TODO: build a full URL
              ephemeral_data = { 'server.io.net.url' => request_url }

              result = context.run_rasp(
                Ext::RASP_SSRF, {}, ephemeral_data, Datadog.configuration.appsec.waf_timeout
              )

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
            end

            super
          end
        end
      end
    end
  end
end
# rubocop:enable Naming/FileName
