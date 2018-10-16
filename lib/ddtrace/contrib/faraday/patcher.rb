require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/faraday/ext'

module Datadog
  module Contrib
    module Faraday
      # Patcher enables patching of 'faraday' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:faraday)
        end

        def patch
          do_once(:faraday) do
            begin
              require 'ddtrace/contrib/faraday/middleware'

              add_pin
              add_middleware
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Faraday integration: #{e}")
            end
          end
        end

        def add_pin
          Pin.new(
            get_option(:service_name),
            app: Ext::APP,
            app_type: Datadog::Ext::AppTypes::WEB,
            tracer: get_option(:tracer)
          ).onto(::Faraday)
        end

        def add_middleware
          ::Faraday::Middleware.register_middleware(ddtrace: Middleware)
        end

        def register_service(name)
          get_option(:tracer).set_service_info(
            name,
            Ext::APP,
            Datadog::Ext::AppTypes::WEB
          )
        end

        def get_option(option)
          Datadog.configuration[:faraday].get_option(option)
        end
      end
    end
  end
end
