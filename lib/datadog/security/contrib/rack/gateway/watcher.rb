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
                      if active_span
                        active_span.set_tag('appsec.action', action)
                        active_span.set_tag('appsec.event', 'true')
                        active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                      end
                      Security::Event.record({ waf_result: result, span: active_span, request: request }, block)
                    end
                  end

                  _action, _result, block = Rack::Reactive::Publisher.publish(op, request)
                end

                next [nil, :block] if block

                stack.call(request)
              end
            end
          end
        end
      end
    end
  end
end
