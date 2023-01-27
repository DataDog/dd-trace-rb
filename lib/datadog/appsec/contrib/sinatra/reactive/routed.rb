# typed: ignore
# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        module Reactive
          # Dispatch data from a Rack request to the WAF context
          module Routed
            WAF_ADDRESSES = [
              Ext::REQUEST_ROUTE_PARAMS
            ].freeze
            private_constant :WAF_ADDRESSES

            def self.publish(op, data)
              _request, route_params = data

              catch(:block) do
                op.publish(Ext::REQUEST_ROUTE_PARAMS, route_params)

                nil
              end
            end

            def self.subscribe(op, waf_context)
              op.subscribe(*WAF_ADDRESSES) do |*values|
                Datadog.logger.debug { "reacted to #{WAF_ADDRESSES.inspect}: #{values.inspect}" }
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
