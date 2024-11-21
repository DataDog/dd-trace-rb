# frozen_string_literal: true

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

            def self.publish(engine, gateway_request)
              catch(:block) do
                # params have been parsed from the request body
                engine.publish('request.body', gateway_request.form_hash)

                nil
              end
            end

            def self.subscribe(engine, waf_context)
              engine.subscribe(*ADDRESSES) do |*values|
                Datadog.logger.debug { "reacted to #{ADDRESSES.inspect}: #{values.inspect}" }
                body = values[0]

                persistent_data = {
                  'server.request.body' => body,
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
