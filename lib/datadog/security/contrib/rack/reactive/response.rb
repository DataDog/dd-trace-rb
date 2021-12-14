require 'datadog/security/contrib/rack/response'

module Datadog
  module Security
    module Contrib
      module Rack
        module Reactive
          module Response
            def self.publish(op, response)
              catch(:block) do
                op.publish('response.status', Rack::Response.status(response))

                nil
              end
            end

            def self.subscribe(op, waf_context)
              addresses = [
                'response.status',
              ]

              op.subscribe(*addresses) do |*values|
                Datadog.logger.debug { "reacted to #{addresses.inspect}: #{values.inspect}" }

                response_status = values[0]

                waf_args = {
                  'server.response.status' => response_status.to_s,
                }

                # TODO: this check is too low level
                # TODO: raise a proper exception
                raise if waf_context.context_obj.null?

                action, result = waf_context.run(waf_args)

                # TODO: encapsulate return array in a type
                case action
                when :monitor
                  Datadog.logger.debug { "WAF: #{result.inspect}" }
                  yield [action, result, false]
                when :block
                  Datadog.logger.debug { "WAF: #{result.inspect}" }
                  yield [action, result, true]
                  throw(:block, [action, result, true])
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
              end
            end
          end
        end
      end
    end
  end
end
