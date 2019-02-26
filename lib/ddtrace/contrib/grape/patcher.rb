require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'

require 'ddtrace/contrib/grape/ext'
require 'ddtrace/contrib/grape/endpoint'
require 'ddtrace/contrib/grape/instrumentation'

module Datadog
  module Contrib
    module Grape
      # Patcher enables patching of 'grape' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:grape)
        end

        def patch
          do_once(:grape) do
            begin
              # Patch endpoints
              ::Grape::Endpoint.send(:include, Instrumentation)


              # Attach a Pin object globally and set the service once
              pin = Datadog::Pin.new(
                get_option(:service_name),
                app: Ext::APP,
                app_type: Datadog::Ext::AppTypes::WEB,
                tracer: get_option(:tracer)
              )
              pin.onto(::Grape)

              # Subscribe to ActiveSupport events
              Datadog::Contrib::Grape::Endpoint.subscribe
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Grape integration: #{e}")
            end
          end
        end

        def get_option(option)
          Datadog.configuration[:grape].get_option(option)
        end
      end
    end
  end
end
