# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        module Reactive
          # Dispatch data from a Sinatra request to the WAF context
          module Routed
            ADDRESSES = [
              'sinatra.request.route_params',
            ].freeze
            private_constant :ADDRESSES

            def self.publish(op, data)
              _request, route_params = data

              catch(:block) do
                op.publish('sinatra.request.route_params', route_params.params)

                nil
              end
            end

            def self.subscribe(op, waf_context)
              op.subscribe(*ADDRESSES) do |*values|
                Datadog.logger.debug { "reacted to #{ADDRESSES.inspect}: #{values.inspect}" }
                path_params = values[0]

                waf_args = {
                  'server.request.path_params' => path_params,
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
