require 'datadog/security/instrumentation/gateway'
require 'datadog/security/reactive/operation'
require 'datadog/security/contrib/rack/reactive/request'
require 'datadog/security/contrib/rack/reactive/response'
require 'datadog/security/event'


module Datadog
  module Security
    module Contrib
      module Rack
        module Gateway
          module Watcher
            def self.watch
              Instrumentation.gateway.watch('rack.request') do |stack, request|
                block = false
                event = nil
                waf_context = request.env['datadog.waf.context']

                Security::Reactive::Operation.new('rack.request') do |op|
                  if defined?(Datadog::Tracer) && Datadog.respond_to?(:tracer) && (tracer = Datadog.tracer)
                    root_span = tracer.active_root_span
                    active_span = tracer.active_span

                    Datadog.logger.debug { "root span: #{root_span.span_id}" } if root_span
                    Datadog.logger.debug { "active span: #{active_span.span_id}" } if active_span

                    if root_span
                      root_span.set_tag('_dd.appsec.enabled', 1)
                      root_span.set_tag('_dd.runtime_family', 'ruby')
                    end
                  end

                  Rack::Reactive::Request.subscribe(op, waf_context) do |action, result, block|
                    record = [:block, :monitor].include?(action)
                    if record
                      # TODO: should this hash be an Event instance instead?
                      event =  { waf_result: result, span: active_span, request: request, action: action }
                    end
                  end

                  _action, _result, block = Rack::Reactive::Request.publish(op, request)
                end

                next [nil, [[:block, event]]] if block

                ret, res = stack.call(request)

                if event
                  res = [] unless res
                  res << [:monitor, event]
                end

                [ret, res]
              end

              Instrumentation.gateway.watch('rack.response') do |stack, response|
                block = false
                event = nil
                waf_context = response.instance_eval { @waf_context }

                Security::Reactive::Operation.new('rack.response') do |op|
                  if defined?(Datadog::Tracer) && Datadog.respond_to?(:tracer) && (tracer = Datadog.tracer)
                    root_span = tracer.active_root_span
                    active_span = tracer.active_span

                    Datadog.logger.debug { "root span: #{root_span.span_id}" } if root_span
                    Datadog.logger.debug { "active span: #{active_span.span_id}" } if active_span

                    if root_span
                      root_span.set_tag('_dd.appsec.enabled', 1)
                      root_span.set_tag('_dd.runtime_family', 'ruby')
                    end
                  end

                  Rack::Reactive::Response.subscribe(op, waf_context) do |action, result, block|
                    record = [:block, :monitor].include?(action)
                    if record
                      # TODO: should this hash be an Event instance instead?
                      event =  { waf_result: result, span: active_span, response: response, action: action }
                    end
                  end

                  _action, _result, block = Rack::Reactive::Response.publish(op, response)
                end

                next [nil, [[:block, event]]] if block

                ret, res = stack.call(response)

                if event
                  res = [] unless res
                  res << [:monitor, event]
                end

                [ret, res]
              end
            end
          end
        end
      end
    end
  end
end
