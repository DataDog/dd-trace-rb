require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module DelayedJob
      # Patcher enables patching of 'delayed_job' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:delayed_job)
        end

        def patch
          do_once(:delayed_job) do
            begin
              require 'ddtrace/contrib/delayed_job/plugin'
              add_instrumentation(::Delayed::Worker)
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply DelayedJob integration: #{e}")
            end
          end
        end

        def add_instrumentation(klass)
          klass.plugins << Plugin
        end
      end
    end
  end
end
