module Datadog
  module Tracing
    module Contrib
      module Sinatra
        # Sinatra integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_SINATRA_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_SINATRA_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SINATRA_ANALYTICS_SAMPLE_RATE'.freeze
          RACK_ENV_SINATRA_REQUEST_SPAN = 'datadog.sinatra_request_span'.freeze
          SPAN_RENDER_TEMPLATE = 'sinatra.render_template'.freeze
          SPAN_REQUEST = 'sinatra.request'.freeze
          SPAN_ROUTE = 'sinatra.route'.freeze
          TAG_APP_NAME = 'sinatra.app.name'.freeze
          TAG_COMPONENT = 'sinatra'.freeze
          TAG_OPERATION_RENDER_TEMPLATE = 'render_template'.freeze
          TAG_OPERATION_REQUEST = 'request'.freeze
          TAG_OPERATION_ROUTE = 'route'.freeze
          TAG_ROUTE_PATH = 'sinatra.route.path'.freeze
          TAG_SCRIPT_NAME = 'sinatra.script_name'.freeze
          TAG_TEMPLATE_ENGINE = 'sinatra.template_engine'.freeze
          TAG_TEMPLATE_NAME = 'sinatra.template_name'.freeze

          # === Deprecated: To be removed ===
          RACK_ENV_REQUEST_SPAN = 'datadog.sinatra_request_span'.freeze
          RACK_ENV_MIDDLEWARE_START_TIME = 'datadog.sinatra_middleware_start_time'.freeze
          RACK_ENV_MIDDLEWARE_TRACED = 'datadog.sinatra_middleware_traced'.freeze
          # === Deprecated: To be removed ===
        end
      end
    end
  end
end
