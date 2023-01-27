# typed: ignore
# frozen_string_literal: true

require_relative '../request'
require_relative '../ext'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Reactive
          # Dispatch data from a Rails request to the WAF context
          module Action
            ADDRESSES = [
              Ext::RAILS_REQUEST_BODY,
              Ext::RAILS_REQUEST_ROUTE_PARMS,
            ].freeze

            private_constant :ADDRESSES

            def self.publish(op, request)
              catch(:block) do
                # params have been parsed from the request body
                op.publish(Ext::RAILS_REQUEST_BODY, Rails::Request.parsed_body(request))
                op.publish(Ext::RAILS_REQUEST_ROUTE_PARMS, Rails::Request.route_params(request))

                nil
              end
            end

            def self.subscribe(op, waf_context)
              op.subscribe(*ADDRESSES) do |*values|
                Datadog.logger.debug { "reacted to #{ADDRESSES.inspect}: #{values.inspect}" }
                body = values[0]
                path_params = values[1]

                waf_args = {
                  'server.request.body' => body,
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
