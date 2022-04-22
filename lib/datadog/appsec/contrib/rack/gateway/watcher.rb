# typed: false

require 'datadog/appsec/instrumentation/gateway'
require 'datadog/appsec/reactive/operation'
require 'datadog/appsec/contrib/rack/reactive/request'
require 'datadog/appsec/contrib/rack/reactive/request_body'
require 'datadog/appsec/contrib/rack/reactive/response'
require 'datadog/appsec/event'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Gateway
          # Watcher for Rack gateway events
          module Watcher
            # rubocop:disable Metrics/AbcSize
            # rubocop:disable Metrics/CyclomaticComplexity
            # rubocop:disable Metrics/MethodLength
            # rubocop:disable Metrics/PerceivedComplexity
            def self.watch
              Instrumentation.gateway.watch('rack.request') do |stack, request|
                block = false
                event = nil
                waf_context = request.env['datadog.waf.context']

                AppSec::Reactive::Operation.new('rack.request') do |op|
                  # TODO: factor out
                  if defined?(Datadog::Tracing) && Datadog::Tracing.respond_to?(:active_span)
                    active_trace = Datadog::Tracing.active_trace
                    active_span = Datadog::Tracing.active_span

                    Datadog.logger.debug { "active span: #{active_span.span_id}" } if active_span

                    if active_trace
                      active_trace.set_tag('_dd.appsec.enabled', 1)
                      active_trace.set_tag('_dd.runtime_family', 'ruby')
                    end
                  end

                  Rack::Reactive::Request.subscribe(op, waf_context) do |action, result, _block|
                    record = [:block, :monitor].include?(action)
                    if record
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: active_trace,
                        span: active_span,
                        request: request,
                        action: action
                      }
                    end
                  end

                  _action, _result, block = Rack::Reactive::Request.publish(op, request)
                end

                next [nil, [[:block, event]]] if block

                ret, res = stack.call(request)

                if event
                  res ||= []
                  res << [:monitor, event]
                end

                [ret, res]
              end

              Instrumentation.gateway.watch('rack.response') do |stack, response|
                block = false
                event = nil
                waf_context = response.instance_eval { @waf_context }

                AppSec::Reactive::Operation.new('rack.response') do |op|
                  # TODO: factor out
                  if defined?(Datadog::Tracing) && Datadog::Tracing.respond_to?(:active_span)
                    active_trace = Datadog::Tracing.active_trace
                    active_span = Datadog::Tracing.active_span

                    Datadog.logger.debug { "active span: #{active_span.span_id}" } if active_span

                    if active_trace
                      active_trace.set_tag('_dd.appsec.enabled', 1)
                      active_trace.set_tag('_dd.runtime_family', 'ruby')
                    end
                  end

                  Rack::Reactive::Response.subscribe(op, waf_context) do |action, result, _block|
                    record = [:block, :monitor].include?(action)
                    if record
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: active_trace,
                        span: active_span,
                        response: response,
                        action: action
                      }
                    end
                  end

                  _action, _result, block = Rack::Reactive::Response.publish(op, response)
                end

                next [nil, [[:block, event]]] if block

                ret, res = stack.call(response)

                if event
                  res ||= []
                  res << [:monitor, event]
                end

                [ret, res]
              end

              Instrumentation.gateway.watch('rack.request.body') do |stack, request|
                block = false
                event = nil
                waf_context = request.env['datadog.waf.context']

                AppSec::Reactive::Operation.new('rack.request.body') do |op|
                  # TODO: factor out
                  if defined?(Datadog::Tracing) && Datadog::Tracing.respond_to?(:active_span)
                    active_trace = Datadog::Tracing.active_trace
                    active_span = Datadog::Tracing.active_span

                    Datadog.logger.debug { "active span: #{active_span.span_id}" } if active_span

                    if active_trace
                      active_trace.set_tag('_dd.appsec.enabled', 1)
                      active_trace.set_tag('_dd.runtime_family', 'ruby')
                    end
                  end

                  Rack::Reactive::RequestBody.subscribe(op, waf_context) do |action, result, _block|
                    record = [:block, :monitor].include?(action)
                    if record
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: active_trace,
                        span: active_span,
                        request: request,
                        action: action
                      }
                    end
                  end

                  _action, _result, block = Rack::Reactive::RequestBody.publish(op, request)
                end

                next [nil, [[:block, event]]] if block

                ret, res = stack.call(request)

                if event
                  res ||= []
                  res << [:monitor, event]
                end

                [ret, res]
              end
            end
            # rubocop:enable Metrics/AbcSize
            # rubocop:enable Metrics/CyclomaticComplexity
            # rubocop:enable Metrics/MethodLength
            # rubocop:enable Metrics/PerceivedComplexity
          end
        end
      end
    end
  end
end
