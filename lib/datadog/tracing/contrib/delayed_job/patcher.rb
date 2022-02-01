# typed: false
require 'datadog/tracing/contrib/delayed_job/integration'
require 'datadog/tracing/contrib/patcher'

module Datadog
  module Tracing
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
            require 'datadog/tracing/contrib/delayed_job/plugin'
            add_instrumentation(::Delayed::Worker)
          end

          def add_instrumentation(klass)
            klass.plugins << Plugin
          end
        end
      end
    end
  end
end
