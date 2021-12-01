require 'datadog/security/instrumentation/gateway'
require 'datadog/security/reactive/operation'
require 'datadog/security/contrib/rack/reactive/subscriber'
require 'datadog/security/contrib/rack/reactive/publisher'

module Datadog
  module Security
    module Contrib
      module Rack
        module Gateway
          module Watcher
            def self.watch
              Instrumentation.gateway.watch('rack.request') do |request|
                block = false

                waf_context = request.env['datadog.waf.context']

                Datadog::Security::Reactive::Operation.new('rack.request') do |op|
                  if defined?(Datadog::Tracer) && Datadog.respond_to?(:tracer) && (tracer = Datadog.tracer)
                    root_span = tracer.active_root_span
                    active_span = tracer.active_span

                    Datadog.logger.debug { "root span: #{root_span.span_id}" } if root_span
                    Datadog.logger.debug { "active span: #{active_span.span_id}" } if active_span

                    root_span.set_tag('_dd.appsec.enabled', 1)
                    root_span.set_tag('_dd.runtime_family', 'ruby')
                  end

                  Reactive::Subscriber.subscribe(op, waf_context, active_span, request)
                  block = Reactive::Publisher.publish(op, request)
                end

                block
              end
            end
          end
        end
      end
    end
  end
end
