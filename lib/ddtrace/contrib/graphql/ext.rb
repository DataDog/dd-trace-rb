# typed: true
module Datadog
  module Contrib
    module GraphQL
      # GraphQL integration constants
      # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
      module Ext
        APP = 'ruby-graphql'.freeze
        ENV_ENABLED = 'DD_TRACE_GRAPHQL_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_GRAPHQL_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_GRAPHQL_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'ruby-graphql'.freeze
      end
    end
  end
end
