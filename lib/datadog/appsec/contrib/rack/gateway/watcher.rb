# frozen_string_literal: true

require_relative '../../../instrumentation/gateway'
require_relative '../../../event'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Gateway
          # Watcher for Rack gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_request(gateway)
                watch_response(gateway)
                watch_request_body(gateway)
              end

              def watch_request(gateway = Instrumentation.gateway)
                gateway.watch('rack.request', :appsec) do |stack, gateway_request|
                  context = gateway_request.env[Datadog::AppSec::Ext::CONTEXT_KEY]

                  persistent_data = {
                    'server.request.cookies' => gateway_request.cookies,
                    'server.request.query' => gateway_request.query,
                    'server.request.uri.raw' => gateway_request.fullpath,
                    'server.request.headers' => gateway_request.headers,
                    'server.request.headers.no_cookies' => gateway_request.headers.dup.tap { |h| h.delete('cookie') },
                    'http.client_ip' => gateway_request.client_ip,
                    'server.request.method' => gateway_request.method
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

              def watch_response(gateway = Instrumentation.gateway)
                gateway.watch('rack.response', :appsec) do |stack, gateway_response|
                  context = gateway_response.context

                  persistent_data = {
                    'server.response.status' => gateway_response.status.to_s,
                    'server.response.headers' => gateway_response.headers,
                    'server.response.headers.no_cookies' => gateway_response.headers.dup.tap { |h| h.delete('set-cookie') }
                  }

                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match?
                    Datadog::AppSec::Event.tag_and_keep!(context, result)

                    context.events << {
                      waf_result: result,
                      trace: context.trace,
                      span: context.span,
                      response: gateway_response,
                      actions: result.actions
                    }

                    Datadog::AppSec::ActionsHandler.handle(result.actions)
                  end

                  stack.call(gateway_response.response)
                end
              end

              def watch_request_body(gateway = Instrumentation.gateway)
                gateway.watch('rack.request.body', :appsec) do |stack, gateway_request|
                  context = gateway_request.env[Datadog::AppSec::Ext::CONTEXT_KEY]

                  persistent_data = {
                    'server.request.body' => gateway_request.form_hash
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
