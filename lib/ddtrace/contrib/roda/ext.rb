module Datadog
  module Contrib
    module Roda
      # Roda integration constants
      module Ext
        APP = 'roda'.freeze
        SERVICE_NAME = 'roda'.freeze

        URL = 'url'.freeze
        METHOD = 'method'.freeze

        SPAN_REQUEST = 'roda.request'.freeze

        SPAN_ENDPOINT_RENDER = 'roda.endpoint_render'.freeze
        SPAN_ENDPOINT_RUN = 'roda.endpoint_run'.freeze
        SPAN_ENDPOINT_RUN_FILTERS = 'roda.endpoint_run_filters'.freeze

        TAG_FILTER_TYPE = 'roda.filter.type'.freeze
        TAG_ROUTE_ENDPOINT = 'roda.route.endpoint'.freeze
        TAG_ROUTE_PATH = 'roda.route.path'.freeze
      end
    end
  end
end
