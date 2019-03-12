module Datadog
  module Contrib
    module GraphQL
      # GraphQL integration constants
      module Ext
        APP = 'ruby-graphql'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_GRAPHQL_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_GRAPHQL_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'ruby-graphql'.freeze
      end
    end
  end
end
