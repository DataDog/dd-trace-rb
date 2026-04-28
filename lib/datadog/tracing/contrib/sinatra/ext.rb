# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Sinatra
        # Sinatra integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_SINATRA_ENABLED'
          ENV_DISTRIBUTED_TRACING = 'DD_TRACE_SINATRA_DISTRIBUTED_TRACING'
          # @!visibility private
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_SINATRA_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SINATRA_ANALYTICS_SAMPLE_RATE'
          ENV_SERVICE_NAME = 'DD_TRACE_SINATRA_SERVICE_NAME'
          ENV_HEADERS = 'DD_TRACE_SINATRA_HEADERS'
          ENV_RESOURCE_SCRIPT_NAMES = 'DD_TRACE_SINATRA_RESOURCE_SCRIPT_NAMES'
          RACK_ENV_SINATRA_REQUEST_SPAN = 'datadog.sinatra_request_span'
          SPAN_RENDER_TEMPLATE = 'sinatra.render_template'
          SPAN_REQUEST = 'sinatra.request'
          SPAN_ROUTE = 'sinatra.route'
          TAG_APP_NAME = 'sinatra.app.name'
          TAG_COMPONENT = 'sinatra'
          TAG_OPERATION_RENDER_TEMPLATE = 'render_template'
          TAG_OPERATION_REQUEST = 'request'
          TAG_OPERATION_ROUTE = 'route'
          TAG_ROUTE_PATH = 'sinatra.route.path'
          TAG_SCRIPT_NAME = 'sinatra.script_name'
          TAG_TEMPLATE_ENGINE = 'sinatra.template_engine'
          TAG_TEMPLATE_NAME = 'sinatra.template_name'
        end
      end
    end
  end
end
