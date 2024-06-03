# frozen_string_literal: true

require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        module Gateway
          # Gateway Request argument. Normalized extration of data from Rack::Request
          class Resolve < Instrumentation::Gateway::Argument
            attr_reader :arguments, :query

            def initialize(arguments, query)
              super()
              @arguments = arguments
              @query = query
            end
          end
        end
      end
    end
  end
end
