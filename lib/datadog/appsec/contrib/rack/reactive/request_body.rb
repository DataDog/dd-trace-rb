# frozen_string_literal: true

require_relative '../request'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Reactive
          # Dispatch data from a Rack request to the WAF context
          module RequestBody
            ADDRESSES = [
              'request.body',
            ].freeze
            private_constant :ADDRESSES

            def self.publish(op, request)
              catch(:block) do
                # params have been parsed from the request body
                op.publish('request.body', Rack::Request.form_hash(request))

                nil
              end
            end

            def self.subscribe(op, waf_context)
              op.subscribe(*ADDRESSES) do |*values|
                Datadog.logger.debug { "reacted to #{ADDRESSES.inspect}: #{values.inspect}" }
                body = values[0]

                waf_args = {
                  'server.request.body' => body,
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
