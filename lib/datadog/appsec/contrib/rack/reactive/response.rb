# typed: true

require_relative '../response'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Reactive
          # Dispatch data from a Rack response to the WAF context
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

                waf_timeout = Datadog::AppSec.settings.waf_timeout
                action, result = waf_context.run(waf_args, waf_timeout)

                Datadog.logger.debug { "WAF TIMEOUT: #{result.inspect}" } if result.timeout

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
