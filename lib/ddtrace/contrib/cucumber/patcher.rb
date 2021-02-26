require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/cucumber/instrumentation'

module Datadog
  module Contrib
    module Cucumber
      # Patcher enables patching of 'cucumber' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          ::Cucumber::Runtime.send(:include, Instrumentation)
          # force blocking flush before at_exit shutdown! hook
          at_exit { Datadog.tracer.writer.worker.flush_data }
        end
      end
    end
  end
end
