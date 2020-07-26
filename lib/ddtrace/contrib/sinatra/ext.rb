module Datadog
  module Contrib
    module Sinatra
      # Sinatra integration constants
      module Ext
        APP = 'sinatra'.freeze
        ENV_ENABLED = 'DD_TRACE_SINATRA_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_SINATRA_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_SINATRA_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SINATRA_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_SINATRA_ANALYTICS_SAMPLE_RATE'.freeze
        RACK_ENV_REQUEST_SPAN = 'datadog.sinatra_request_span'.freeze
        RACK_ENV_MIDDLEWARE_START_TIME = 'datadog.sinatra_middleware_start_time'.freeze
        RACK_ENV_MIDDLEWARE_TRACED = 'datadog.sinatra_middleware_traced'.freeze
        SERVICE_NAME = 'sinatra'.freeze
        SPAN_RENDER_TEMPLATE = 'sinatra.render_template'.freeze
        SPAN_REQUEST = 'sinatra.request'.freeze
        SPAN_ROUTE = 'sinatra.route'.freeze
        TAG_APP_NAME = 'sinatra.app.name'.freeze
        TAG_ROUTE_PATH = 'sinatra.route.path'.freeze
        TAG_SCRIPT_NAME = 'sinatra.script_name'.freeze
        TAG_TEMPLATE_ENGINE = 'sinatra.template_engine'.freeze
        TAG_TEMPLATE_NAME = 'sinatra.template_name'.freeze
      end
    end
  end
end
