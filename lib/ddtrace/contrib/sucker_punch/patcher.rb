require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module SuckerPunch
      # Patcher enables patching of 'sucker_punch' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:sucker_punch)
        end

        def patch
          do_once(:sucker_punch) do
            begin
              require 'ddtrace/contrib/sucker_punch/exception_handler'
              require 'ddtrace/contrib/sucker_punch/instrumentation'

              add_pin!
              ExceptionHandler.patch!
              Instrumentation.patch!
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply SuckerPunch integration: #{e}")
            end
          end
        end

        def add_pin!
          Pin.new(get_option(:service_name), app: Integration::APP, app_type: Ext::AppTypes::WORKER).tap do |pin|
            pin.onto(::SuckerPunch)
          end
        end

        def get_option(option)
          Datadog.configuration[:sucker_punch].get_option(option)
        end
      end
    end
  end
end
