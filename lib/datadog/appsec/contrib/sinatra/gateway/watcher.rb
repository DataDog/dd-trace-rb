# frozen_string_literal: true

require_relative '../../../event'
require_relative '../../../trace_keeper'
require_relative '../../../security_event'
require_relative '../../../instrumentation/gateway'

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        module Gateway
          # Watcher for Sinatra gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_request_dispatch(gateway)
                watch_request_routed(gateway)
                watch_response_body_json(gateway)
              end

              def watch_request_dispatch(gateway = Instrumentation.gateway)
                gateway.watch('sinatra.request.dispatch', :appsec) do |stack, gateway_request|
                  context = gateway_request.env[AppSec::Ext::CONTEXT_KEY] # : Context

                  context.state[:web_framework] = 'sinatra'

                  persistent_data = {
                    'server.request.body' => gateway_request.form_hash
                  }

                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match? || !result.attributes.empty?
                    context.events.push(
                      AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                    )
                  end

                  if result.match?
                    AppSec::Event.tag(context, result)
                    TraceKeeper.keep!(context.trace) if result.keep?

                    AppSec::ActionsHandler.handle(result.actions)
                  end

                  stack.call(gateway_request.request)
                end
              end

              def watch_request_routed(gateway = Instrumentation.gateway)
                gateway.watch('sinatra.request.routed', :appsec) do |stack, args|
                  gateway_request, gateway_route_params = args # : [Gateway::Request, Gateway::RouteParams]
                  context = gateway_request.env[AppSec::Ext::CONTEXT_KEY] # : Context

                  persistent_data = {
                    'server.request.path_params' => gateway_route_params.params
                  }

                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match?
                    AppSec::Event.tag(context, result)
                    TraceKeeper.keep!(context.trace) if result.keep?

                    context.events.push(
                      AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                    )

                    AppSec::ActionsHandler.handle(result.actions)
                  end

                  stack.call(gateway_request.request)
                end
              end

              def watch_response_body_json(gateway = Instrumentation.gateway)
                gateway.watch('sinatra.response.body.json', :appsec) do |stack, container|
                  context = container.context # : Context

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
