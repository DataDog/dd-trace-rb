# frozen_string_literal: true

require_relative "../patcher"
require_relative "data_streams"
require_relative "ext"
require_relative "events"
require_relative "log_injection"

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
            inject_log_correlation
            inject_data_streams
          end

          def inject_log_correlation
            ::ActiveSupport.on_load(:active_job) do
              if ::ActiveJob.gem_version < Gem::Version.new("6.0.0")
                include LogInjection::AroundPerformPatch
              else
                include LogInjection::PerformNowPatch
              end
            end
          end

          def inject_data_streams
            # ActiveJob 4.2 deserializes jobs through a class method rather than the
            # instance method, so the DSM pathway can only be propagated on 5.0+.
            return if ::ActiveJob.gem_version < Gem::Version.new("5.0.0")

            ::ActiveSupport.on_load(:active_job) do
              prepend DataStreams
            end
          end
        end
      end
    end
  end
end
