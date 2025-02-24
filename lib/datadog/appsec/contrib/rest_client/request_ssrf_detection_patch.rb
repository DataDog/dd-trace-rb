# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module RestClient
        # Module that adds SSRF detection to RestClient::Request#execute
        module RequestSSRFDetectionPatch
          def execute(&block)
            return super unless AppSec.rasp_enabled? && AppSec.active_context

            context = AppSec.active_context

            ephemeral_data = { 'server.io.net.url' => url }
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, Datadog.configuration.appsec.waf_timeout)

            if result.match?
              Datadog::AppSec::Event.tag_and_keep!(context, result)

              context.events << {
                waf_result: result,
                trace: context.trace,
                span: context.span,
                request_url: url,
                actions: result.actions
              }

              ActionsHandler.handle(result.actions)
            end

            super(&block)
          end
        end
      end
    end
  end
end
