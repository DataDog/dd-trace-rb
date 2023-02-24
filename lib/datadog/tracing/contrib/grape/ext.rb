module Datadog
  module Tracing
    module Contrib
      module Grape
        # Grape integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_GRAPE_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_GRAPE_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_GRAPE_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_ENDPOINT_RENDER = 'grape.endpoint_render'.freeze
          SPAN_ENDPOINT_RUN = 'grape.endpoint_run'.freeze
          SPAN_ENDPOINT_RUN_FILTERS = 'grape.endpoint_run_filters'.freeze
          TAG_COMPONENT = 'grape'.freeze
          TAG_FILTER_TYPE = 'grape.filter.type'.freeze
          TAG_OPERATION_ENDPOINT_RENDER = 'endpoint_render'.freeze
          TAG_OPERATION_ENDPOINT_RUN = 'endpoint_run'.freeze
          TAG_OPERATION_ENDPOINT_RUN_FILTERS = 'endpoint_run_filters'.freeze
          TAG_ROUTE_ENDPOINT = 'grape.route.endpoint'.freeze
          TAG_ROUTE_PATH = 'grape.route.path'.freeze
          TAG_ROUTE_METHOD = 'grape.route.method'.freeze
        end
      end
    end
  end
end
