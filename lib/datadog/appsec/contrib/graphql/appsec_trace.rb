# frozen_string_literal: true

require 'json'
require_relative 'gateway/multiplex'
require_relative '../../instrumentation/gateway'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        # These methods will be called by the GraphQL runtime to send the variables to the WAF.
        # We actually don't need to create any span/trace.
        module AppSecTrace
          def execute_multiplex(multiplex:)
            return super unless Datadog::AppSec.enabled?

            gateway_multiplex = Gateway::Multiplex.new(multiplex)

            multiplex_return, multiplex_response = Instrumentation.gateway.push('graphql.multiplex', gateway_multiplex) do
              super
            end

            # Returns an error * the number of queries so that the entire multiplex is blocked
            if multiplex_response
              blocked_event = multiplex_response.find { |action, _options| action == :block }
              multiplex_return = AppSec::Response.graphql_response(gateway_multiplex) if blocked_event
            end

            multiplex_return
          end
        end
      end
    end
  end
end
