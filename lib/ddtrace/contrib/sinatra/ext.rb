module Datadog
  module Contrib
    module Sinatra
      # Sinatra integration constants
      module Ext
        APP = 'sinatra'.freeze
        SERVICE_NAME = 'sinatra'.freeze

        RACK_ENV_REQUEST_SPAN = 'datadog.sinatra_request_span'.freeze

        SPAN_RENDER_TEMPLATE = 'sinatra.render_template'.freeze
        SPAN_REQUEST = 'sinatra.request'.freeze

        TAG_ROUTE_PATH = 'sinatra.route.path'.freeze
        TAG_TEMPLATE_NAME = 'sinatra.template_name'.freeze
      end
    end
  end
end
