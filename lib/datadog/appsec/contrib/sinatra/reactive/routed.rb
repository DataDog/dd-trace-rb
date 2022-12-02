# typed: true

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        module Reactive
          # Dispatch data from a Rack request to the WAF context
          module Routed
            def self.publish(op, data)
              _request, route_params = data

              catch(:block) do
                op.publish('sinatra.request.route_params', route_params)

                nil
              end
            end

            def self.subscribe(op, waf_context)
              addresses = [
                'sinatra.request.route_params',
              ]

              op.subscribe(*addresses) do |*values|
                Datadog.logger.debug { "reacted to #{addresses.inspect}: #{values.inspect}" }
                path_params = values[0]

                waf_args = {
                  'server.request.path_params' => path_params,
                }

                waf_timeout = Datadog::AppSec.settings.waf_timeout
                result = waf_context.run(waf_args, waf_timeout)

                Datadog.logger.debug { "WAF TIMEOUT: #{result.inspect}" } if result.timeout

                case result.status
                when :match
                  Datadog.logger.debug { "WAF: #{result.inspect}" }

                  block = result.actions.include?('block')

                  yield [result, block]

                  throw(:block, [result, true]) if block
                when :ok
                  Datadog.logger.debug { "WAF OK: #{result.inspect}" }
                when :invalid_call
                  Datadog.logger.debug { "WAF CALL ERROR: #{result.inspect}" }
                when :invalid_rule, :invalid_flow, :no_rule
                  Datadog.logger.debug { "WAF RULE ERROR: #{result.inspect}" }
                else
                  Datadog.logger.debug { "WAF UNKNOWN: #{result.status.inspect} #{result.inspect}" }
                end
              end
            end
          end
        end
      end
    end
  end
end
