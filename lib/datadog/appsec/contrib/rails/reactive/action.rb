# frozen_string_literal: true

require_relative '../request'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Reactive
          # Dispatch data from a Rails request to the WAF context
          module Action
            ADDRESSES = [
              'rails.request.body',
              'rails.request.route_params',
            ].freeze
            private_constant :ADDRESSES

            def self.publish(engine, gateway_request)
              catch(:block) do
                # params have been parsed from the request body
                engine.publish('rails.request.body', gateway_request.parsed_body)
                engine.publish('rails.request.route_params', gateway_request.route_params)

                nil
              end
            end

            def self.subscribe(engine, waf_context)
              engine.subscribe(*ADDRESSES) do |*values|
                Datadog.logger.debug { "reacted to #{ADDRESSES.inspect}: #{values.inspect}" }
                body = values[0]
                path_params = values[1]

                persistent_data = {
                  'server.request.body' => body,
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
