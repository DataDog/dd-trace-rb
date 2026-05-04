# frozen_string_literal: true

require_relative '../../../event'
require_relative '../../../trace_keeper'
require_relative '../../../security_event'
require_relative '../../../instrumentation/gateway'
require_relative '../waf_addresses'

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
                gateway.watch('aws_lambda.request.start') do |stack, payload|
                  context = payload.context
                  next stack.call(payload) unless context

                  persistent_data = WAFAddresses.from_request(payload.data)
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

                  stack.call(payload)
                end
              end

              def watch_response(gateway = Instrumentation.gateway)
                gateway.watch('aws_lambda.response.start') do |stack, payload|
                  context = payload.context
                  next stack.call(payload) unless context

                  persistent_data = WAFAddresses.from_response(payload.data)
                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match?
                    AppSec::Event.tag(context, result)
                    TraceKeeper.keep!(context.trace) if result.keep?

                    context.events.push(
                      AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                    )

                    AppSec::ActionsHandler.handle(result.actions)
                  end

                  stack.call(payload)
                end
              end
            end
          end
        end
      end
    end
  end
end
