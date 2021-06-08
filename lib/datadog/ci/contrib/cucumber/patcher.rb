require 'ddtrace/contrib/patcher'
require 'datadog/ci/contrib/cucumber/instrumentation'

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Patcher enables patching of 'cucumber' module.
        module Patcher
          include Datadog::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::Cucumber::Runtime.include(Instrumentation)
          end
        end
      end
    end
  end
end
