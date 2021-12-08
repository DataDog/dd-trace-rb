require 'datadog/security/instrumentation/gateway'
require 'datadog/security/reactive/operation'
require 'datadog/security/contrib/rack/reactive/subscriber'
require 'datadog/security/contrib/rack/reactive/publisher'
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

                  Rack::Reactive::Subscriber.subscribe(op, waf_context) do |action, result, block|
                    record = [:block, :monitor].include?(action)
                    if record
                      # TODO: move into event record method?
                      if active_span
                        active_span.set_tag('appsec.action', action)
                        active_span.set_tag('appsec.event', 'true')
                        active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                      end
                      # TODO: should this hash be an Event instance instead?
                      event =  { waf_result: result, span: active_span, request: request }
                    end
                  end

                  _action, _result, block = Rack::Reactive::Publisher.publish(op, request)
                end

                next [nil, [[:block, event]]] if block

                ret, res = stack.call(request)

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
