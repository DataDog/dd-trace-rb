# frozen_string_literal: true

require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        module Gateway
          # Gateway Request argument. Normalized extration of data from Rack::Request
          class Execute < Instrumentation::Gateway::Argument
            attr_reader :variables, :query

            def initialize(query)
              super()
              @query = query
              @variables = query.provided_variables
            end
          end
        end
      end
    end
  end
end
