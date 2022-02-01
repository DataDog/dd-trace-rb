# typed: true
require 'datadog/tracing'
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/sucker_punch/ext'
require 'datadog/tracing/contrib/sucker_punch/integration'

module Datadog
  module Tracing
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
            require 'datadog/tracing/contrib/sucker_punch/exception_handler'
            require 'datadog/tracing/contrib/sucker_punch/instrumentation'

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
end
