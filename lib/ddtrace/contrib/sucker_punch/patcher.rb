# typed: true
require 'datadog/tracing'
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/sucker_punch/ext'
require 'ddtrace/contrib/sucker_punch/integration'

module Datadog
  module Contrib
    module SuckerPunch
      # Patcher enables patching of 'sucker_punch' module.
      module Patcher
        include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/contrib/sucker_punch/exception_handler'
          require 'ddtrace/contrib/sucker_punch/instrumentation'

          ExceptionHandler.patch!
          Instrumentation.patch!
        end

        def get_option(option)
          Tracing.configuration[:sucker_punch].get_option(option)
        end
      end
    end
  end
end
