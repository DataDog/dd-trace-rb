# frozen_string_literal: true

require_relative 'ext'
require_relative 'gateway/execute'
require_relative 'gateway/resolve'
require_relative '../../instrumentation/gateway'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        # These methods will be called by the GraphQL runtime to send the variables to the WAF.
        # We actually don't need to create any span/trace.
        module AppSecTrace
          # Error handling
          def execute_multiplex(multiplex:)
            catch(Ext::QUERY_INTERRUPT) do
              super
            end
          end

          def execute_query(query:)
            gateway_execute = Gateway::Execute.new(query)

            execute_return, _execute_response = Instrumentation.gateway.push('graphql.execute', gateway_execute) do
              super
            end

            execute_return
          end

          def execute_field(**kwargs)
            gateway_resolve = Gateway::Resolve.new(kwargs[:arguments], kwargs[:query], kwargs[:field])

            resolve_return, _resolve_response = Instrumentation.gateway.push('graphql.resolve', gateway_resolve) do
              super(**kwargs)
            end

            resolve_return
          end

          def execute_field_lazy(**kwargs)
            gateway_resolve = Gateway::Resolve.new(kwargs[:arguments], kwargs[:query], kwargs[:field])

            resolve_return, _resolve_response = Instrumentation.gateway.push('graphql.resolve', gateway_resolve) do
              super(**kwargs)
            end

            resolve_return
          end
        end
      end
    end
  end
end
