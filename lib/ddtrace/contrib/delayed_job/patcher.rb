require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module DelayedJob
      # Patcher enables patching of 'delayed_job' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/contrib/delayed_job/plugin'
          add_instrumentation(::Delayed::Worker)
        end

        def add_instrumentation(klass)
          klass.plugins << Plugin
        end
      end
    end
  end
end
