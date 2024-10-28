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

                next if result.status != :match

                yield result
                throw(:block, true) unless result.actions.empty?
              end
            end
          end
        end
      end
    end
  end
end
