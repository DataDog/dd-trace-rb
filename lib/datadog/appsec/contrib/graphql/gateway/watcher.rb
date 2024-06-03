# frozen_string_literal: true

require_relative '../../../instrumentation/gateway'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        module Gateway
          # Watcher for Rack gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_execute(gateway)
                watch_resolve(gateway)
              end

              def watch_execute(gateway = Instrumentation.gateway)
                gateway.watch('graphql.execute', :appsec) do |stack, gateway_execute|
                  if gateway_execute.variables[:query] == 'threat'
                    raise 'Vars (in execute) will be analyzed by the WAF and blocked if a threat is detected'
                  end

                  ret, res = stack.call(gateway_execute.variables)

                  [ret, res]
                end
              end

              def watch_resolve(gateway = Instrumentation.gateway)
                gateway.watch('graphql.resolve', :appsec) do |stack, gateway_resolve|
                  if gateway_resolve.arguments[:query] == 'threat'
                    raise 'Args (in resolve) will be analyzed by the WAF and blocked if a threat is detected'
                  end

                  ret, res = stack.call(gateway_resolve.arguments)

                  [ret, res]
                end
              end
            end
          end
        end
      end
    end
  end
end
