# frozen_string_literal: true

require_relative '../../../instrumentation/gateway'
require_relative '../../../event'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Gateway
          # Watcher for Rails gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_request_action(gateway)
              end

              def watch_request_action(gateway = Instrumentation.gateway)
                gateway.watch('rails.request.action', :appsec) do |stack, gateway_request|
                  context = gateway_request.env[Datadog::AppSec::Ext::CONTEXT_KEY]

                  persistent_data = {
                    'server.request.body' => gateway_request.parsed_body,
                    'server.request.path_params' => gateway_request.route_params
                  }

                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match?
                    Datadog::AppSec::Event.tag_and_keep!(context, result)

                    context.events << {
                      waf_result: result,
                      trace: context.trace,
                      span: context.span,
                      request: gateway_request,
                      actions: result.actions
                    }

                    Datadog::AppSec::ActionsHandler.handle(result.actions)
                  end

                  stack.call(gateway_request.request)
                end
              end
            end
          end
        end
      end
    end
  end
end
