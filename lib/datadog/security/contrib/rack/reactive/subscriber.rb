require 'datadog/security/event'

module Datadog
  module Security
    module Contrib
      module Rack
        module Reactive
          module Subscriber
            def self.subscribe(op, waf_context, active_span, request)
              addresses = [
                'request.headers',
                'request.uri.raw',
                'request.query',
                'request.cookies',
                'request.body.raw',
                # TODO: 'request.path_params',
              ]

              op.subscribe(*addresses) do |*values|
                Datadog.logger.debug { "reacted to #{addresses.inspect}: #{values.inspect}" }
                headers = values[0]
                headers_no_cookies = headers.dup.tap { |h| h.delete('cookie') }
                uri_raw = values[1]
                query = values[2]
                cookies = values[3]
                body = values[4]
                Datadog.logger.debug { "headers: #{headers}" }
                Datadog.logger.debug { "headers_no_cookie: #{headers_no_cookies}" }

                waf_args = {
                  'server.request.cookies' => cookies,
                  'server.request.body.raw' => body,
                  'server.request.query' => query,
                  'server.request.uri.raw' => uri_raw,
                  'server.request.headers' => headers,
                  'server.request.headers.no_cookies' => headers_no_cookies,
                  # TODO: 'server.request.path_params' => path_params,
                }

                # TODO: this check is too low level
                # TODO: raise a proper exception
                raise if waf_context.context_obj.null?

                action, result = waf_context.run(waf_args)

                case action
                when :monitor
                  Datadog.logger.debug { "WAF: #{result.inspect}" }
                  if active_span
                    active_span.set_tag('appsec.action', 'monitor')
                    active_span.set_tag('appsec.event', 'true')
                    active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                  end
                  Event.record({ waf_result: result, span: active_span, request: request }, false)
                when :block
                  Datadog.logger.debug { "WAF: #{result.inspect}" }
                  if active_span
                    active_span.set_tag('appsec.action', 'block')
                    active_span.set_tag('appsec.event', 'true')
                    active_span.set_tag(Datadog::Ext::ManualTracing::TAG_KEEP, true)
                  end
                  Event.record({ waf_result: result, span: active_span, request: request }, true)
                  block = true
                when :good
                  Datadog.logger.debug { "WAF OK: #{result.inspect}" }
                when :timeout
                  Datadog.logger.debug { "WAF TIMEOUT: #{result.inspect}" }
                when :invalid_call
                  Datadog.logger.debug { "WAF CALL ERROR: #{result.inspect}" }
                when :invalid_rule, :invalid_flow, :no_rule
                  Datadog.logger.debug { "WAF RULE ERROR: #{result.inspect}" }
                else
                  Datadog.logger.debug { "WAF UNKNOWN: #{action.inspect} #{result.inspect}" }
                end

                throw(:block, :block) if block
              end
            end
          end
        end
      end
    end
  end
end
