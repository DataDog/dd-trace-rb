# typed: true

require 'datadog/appsec/contrib/rack/request'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Reactive
          # Dispatch data from a Rack request to the WAF context
          module RequestBody
            def self.publish(op, request)
              catch(:block) do
                # params have been parsed from the request body
                op.publish('request.body', Rack::Request.form_hash(request))

                nil
              end
            end

            def self.subscribe(op, waf_context)
              addresses = [
                'request.body',
              ]

              op.subscribe(*addresses) do |*values|
                Datadog.logger.debug { "reacted to #{addresses.inspect}: #{values.inspect}" }
                body = values[0]

                waf_args = {
                  'server.request.body' => body,
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
