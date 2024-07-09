# frozen_string_literal: true

require 'json'
require_relative 'ext'
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
              if blocked_event
                multiplex_return = []
                gateway_multiplex.queries.each do |query|
                  query_result = ::GraphQL::Query::Result.new(
                    query: query,
                    values: JSON.parse(AppSec::Response.content_json)
                  )
                  multiplex_return << query_result
                end
              end
            end

            multiplex_return
          end

          private

          def active_trace
            return unless defined?(Datadog::Tracing)

            Datadog::Tracing.active_trace
          end

          def active_span
            return unless defined?(Datadog::Tracing)

            Datadog::Tracing.active_span
          end
        end
      end
    end
  end
end
