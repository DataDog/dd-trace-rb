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

            def self.publish(engine, data)
              _request, route_params = data

              catch(:block) do
                engine.publish('sinatra.request.route_params', route_params.params)

                nil
              end
            end

            def self.subscribe(engine, waf_context)
              engine.subscribe(*ADDRESSES) do |*values|
                Datadog.logger.debug { "reacted to #{ADDRESSES.inspect}: #{values.inspect}" }
                path_params = values[0]

                persistent_data = {
                  'server.request.path_params' => path_params,
                }

                waf_timeout = Datadog.configuration.appsec.waf_timeout
                result = waf_context.run(persistent_data, {}, waf_timeout)

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
