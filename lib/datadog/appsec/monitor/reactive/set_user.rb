# frozen_string_literal: true

module Datadog
  module AppSec
    module Monitor
      module Reactive
        # Dispatch data from Datadog::Kit::Identity.set_user to the WAF context
        module SetUser
          ADDRESSES = [
            'usr.id',
          ].freeze
          private_constant :ADDRESSES

          def self.publish(op, user)
            catch(:block) do
              op.publish('usr.id', user.id)

              nil
            end
          end

          def self.subscribe(op, waf_context)
            op.subscribe(*ADDRESSES) do |*values|
              Datadog.logger.debug { "reacted to #{ADDRESSES.inspect}: #{values.inspect}" }

              user_id = values[0]

              waf_args = {
                'usr.id' => user_id,
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
