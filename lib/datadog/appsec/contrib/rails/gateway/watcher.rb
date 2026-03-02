# frozen_string_literal: true

require_relative '../../../event'
require_relative '../../../trace_keeper'
require_relative '../../../security_event'
require_relative '../../../instrumentation/gateway'
require_relative '../../../../core/utils/only_once'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Gateway
          # Watcher for Rails gateway events
          module Watcher
            WATCH_REQUEST_ACTION_ONCE = Core::Utils::OnlyOnce.new
            WATCH_RESPONSE_BODY_JSON_ONCE = Core::Utils::OnlyOnce.new

            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_request_action(gateway)
                watch_response_body_json(gateway)
              end

              def watch_request_action(gateway = Instrumentation.gateway)
                WATCH_REQUEST_ACTION_ONCE.run do
                  gateway.watch('rails.request.action') do |stack, gateway_request|
                    context = gateway_request.env[AppSec::Ext::CONTEXT_KEY]

                    persistent_data = {
                      'server.request.body' => gateway_request.parsed_body,
                      'server.request.path_params' => gateway_request.route_params
                    }

                    result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                    if result.match?
                      context.events.push(
                        AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                      )

                      AppSec::Event.tag(context, result)
                      TraceKeeper.keep!(context.trace) if result.keep?

                      AppSec::ActionsHandler.handle(result.actions)
                    end

                    stack.call(gateway_request.request)
                  end
                end
              end

              def watch_response_body_json(gateway = Instrumentation.gateway)
                WATCH_RESPONSE_BODY_JSON_ONCE.run do
                  gateway.watch('rails.response.body.json') do |stack, container|
                    context = container.context

                    persistent_data = {
                      'server.response.body' => container.data
                    }
                    result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                    if result.match?
                      context.events.push(
                        AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                      )

                      AppSec::Event.tag(context, result)
                      TraceKeeper.keep!(context.trace) if result.keep?

                      AppSec::ActionsHandler.handle(result.actions)
                    end

                    stack.call(container)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
