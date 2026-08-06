# frozen_string_literal: true

require_relative "../../../event"
require_relative "../../../trace_keeper"
require_relative "../../../security_event"
require_relative "../../../instrumentation/gateway"

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
                watch_response_body_json(gateway)
              end

              def watch_request_action(gateway = Instrumentation.gateway)
                gateway.watch("rails.request.action") do |stack, gateway_request|
                  context = gateway_request.env[AppSec::Ext::CONTEXT_KEY]
                  limit = Datadog.configuration.appsec.body_parsing_size_limit

                  persistent_data = {
                    "server.request.path_params" => gateway_request.route_params,
                  }

                  unless limit.zero?
                    byte_length = gateway_request.body_bytesize(limit)

                    if byte_length
                      # NOTE: Params may be parsed before this hook, leaving the
                      #       body stream at EOF. Keep byte_length unset for that
                      #       case, but still inspect cached params
                      persistent_data["server.request.body.byte_length"] = byte_length if byte_length.positive?

                      if byte_length <= limit
                        body = gateway_request.parsed_body
                        persistent_data["server.request.body"] = body unless body.nil? || body.empty?
                      end
                    end
                  end

                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match?
                    context.events.push(
                      AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span),
                    )

                    AppSec::Event.tag(context, result)
                    TraceKeeper.keep!(context.trace) if result.keep?

                    AppSec::ActionsHandler.handle(result.actions)
                  end

                  stack.call(gateway_request.request)
                end
              end

              def watch_response_body_json(gateway = Instrumentation.gateway)
                gateway.watch("rails.response.body.json") do |stack, container|
                  context = container.context

                  persistent_data = {
                    "server.response.body" => container.data,
                  }
                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match?
                    context.events.push(
                      AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span),
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
