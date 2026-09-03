# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Lograge
        module Instrumentation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          module InstanceMethods
            def custom_options(event)
              return super unless Datadog.configuration.tracing.log_injection
              return super unless Datadog.configuration.tracing[:lograge].enabled

              original_custom_options = super

              # Retrieves trace information for current thread
              correlation = Tracing.correlation
              correlation.to_h.merge(original_custom_options)
            end
          end
        end
      end
    end
  end
end
