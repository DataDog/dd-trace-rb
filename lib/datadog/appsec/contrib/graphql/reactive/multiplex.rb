# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        module Reactive
          # Dispatch data from a GraphQL resolve query to the WAF context
          module Multiplex
            ADDRESSES = [
              'graphql.server.all_resolvers'
            ].freeze
            private_constant :ADDRESSES

            def self.publish(op, gateway_multiplex)
              catch(:block) do
                op.publish('graphql.server.all_resolvers', gateway_multiplex.arguments)

                nil
              end
            end

            def self.subscribe(op, waf_context)
              op.subscribe(*ADDRESSES) do |*values|
                Datadog.logger.debug { "reacted to #{ADDRESSES.inspect}: #{values.inspect}" }
                arguments = values[0]

                waf_args = {
                  'graphql.server.all_resolvers' => arguments
                }

                waf_timeout = Datadog.configuration.appsec.waf_timeout
                result = waf_context.run(waf_args, waf_timeout)

                Datadog.logger.debug { "WAF TIMEOUT: #{result.inspect}" } if result.timeout

                case result.status
                when :match
                  Datadog.logger.debug { "WAF: #{result.inspect}" }

                  yield result
                  throw(:block, true) unless result.actions.empty?
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
