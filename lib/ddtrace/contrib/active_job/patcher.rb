# typed: false
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_job/ext'
require 'ddtrace/contrib/active_job/events'
require 'ddtrace/contrib/active_job/log_injection'

module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        # Patcher enables patching of 'active_job' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            Events.subscribe!
            inject_log_correlation if Tracing.configuration.log_injection
          end

          def inject_log_correlation
            ::ActiveSupport.on_load(:active_job) do
              include LogInjection
            end
          end
        end
      end
    end
  end
end
