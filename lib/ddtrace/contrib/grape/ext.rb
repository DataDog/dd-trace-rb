module Datadog
  module Contrib
    module Grape
      # Grape integration constants
      module Ext
        APP = 'grape'.freeze
        ENV_ENABLED = 'DD_TRACE_GRAPE_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_GRAPE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_GRAPE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_GRAPE_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_GRAPE_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'grape'.freeze
        SPAN_ENDPOINT_RENDER = 'grape.endpoint_render'.freeze
        SPAN_ENDPOINT_RUN = 'grape.endpoint_run'.freeze
        SPAN_ENDPOINT_RUN_FILTERS = 'grape.endpoint_run_filters'.freeze
        TAG_FILTER_TYPE = 'grape.filter.type'.freeze
        TAG_ROUTE_ENDPOINT = 'grape.route.endpoint'.freeze
        TAG_ROUTE_PATH = 'grape.route.path'.freeze
        TAG_ROUTE_METHOD = 'grape.route.method'.freeze
      end
    end
  end
end
