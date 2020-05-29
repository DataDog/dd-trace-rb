require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sucker_punch/ext'

module Datadog
  module Contrib
    module SuckerPunch
      # Patcher enables patching of 'sucker_punch' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/contrib/sucker_punch/exception_handler'
          require 'ddtrace/contrib/sucker_punch/instrumentation'

          add_pin!
          ExceptionHandler.patch!
          Instrumentation.patch!
        end

        def add_pin!
          Pin.new(
            get_option(:service_name),
            app: Ext::APP,
            app_type: Datadog::Ext::AppTypes::WORKER,
            tracer: -> { get_option(:tracer) }
          ).onto(::SuckerPunch)
        end

        def get_option(option)
          Datadog.configuration[:sucker_punch].get_option(option)
        end
      end
    end
  end
end
