module Datadog
  module Contrib
    module Sinatra
      # Sinatra integration constants
      module Ext
        APP = 'sinatra'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_SINATRA_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_SINATRA_ANALYTICS_SAMPLE_RATE'.freeze
        RACK_ENV_REQUEST_SPAN = 'datadog.sinatra_request_span'.freeze
        SERVICE_NAME = 'sinatra'.freeze
        SPAN_RENDER_TEMPLATE = 'sinatra.render_template'.freeze
        SPAN_REQUEST = 'sinatra.request'.freeze
        TAG_ROUTE_PATH = 'sinatra.route.path'.freeze
        TAG_TEMPLATE_NAME = 'sinatra.template_name'.freeze
      end
    end
  end
end
