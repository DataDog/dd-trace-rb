# frozen_string_literal: true

require_relative '../../../event'
require_relative '../../../trace_keeper'
require_relative '../../../security_event'
require_relative '../../../instrumentation/gateway'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        module Gateway
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_request(gateway)
                watch_response(gateway)
              end

              def watch_request(gateway = Instrumentation.gateway)
                gateway.watch('aws_lambda.request.start') do |stack, gateway_request|
                  context = AppSec::Context.active

                  persistent_data = {
                    'server.request.cookies' => gateway_request.cookies,
                    'server.request.query' => gateway_request.query,
                    'server.request.uri.raw' => gateway_request.fullpath,
                    'server.request.headers' => gateway_request.headers,
                    'server.request.headers.no_cookies' => gateway_request.headers.dup.tap { |h| h.delete('cookie') },
                    'http.client_ip' => gateway_request.client_ip,
                    'server.request.method' => gateway_request.method,
                    'server.request.body' => gateway_request.form_hash,
                    'server.request.path_params' => gateway_request.path_parameters,
                  }

                  persistent_data.compact!

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

                  stack.call(gateway_request)
                end
              end

              def watch_response(gateway = Instrumentation.gateway)
                gateway.watch('aws_lambda.response.start') do |stack, gateway_response|
                  context = gateway_response.context

                  persistent_data = {
                    'server.response.status' => gateway_response.status.to_s,
                    'server.response.headers' => gateway_response.headers,
                    'server.response.headers.no_cookies' => gateway_response.headers.dup.tap { |h| h.delete('set-cookie') },
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

                  stack.call(gateway_response.response)
                end
              end
            end
          end
        end
      end
    end
  end
end
