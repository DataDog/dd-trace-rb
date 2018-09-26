module Datadog
  module Contrib
    module Rack
      # Provides instrumentation for `rack`
      module Patcher
        include Base

        DEFAULT_HEADERS = {
          response: [
            'Content-Type',
            'X-Request-ID'
          ]
        }.freeze

        register_as :rack
        option :tracer, default: Datadog.tracer
        option :distributed_tracing, default: false
        option :middleware_names, default: false
        option :quantize, default: {}
        option :application
        option :service_name, default: 'rack', depends_on: [:tracer] do |value|
          get_option(:tracer).set_service_info(value, 'rack', Ext::AppTypes::WEB)
          value
        end
        option :request_queuing, default: false
        option :web_service_name, default: 'web-server', depends_on: [:tracer, :request_queuing] do |value|
          if get_option(:request_queuing)
            get_option(:tracer).set_service_info(value, 'webserver', Ext::AppTypes::WEB)
          end
          value
        end
        option :headers, default: DEFAULT_HEADERS

        module_function

        def patch
          unless patched?
            require_relative 'middlewares'
            @patched = true
          end

          @patched
        end

        def patched?
          @patched ||= false
        end
      end
    end
  end
end
