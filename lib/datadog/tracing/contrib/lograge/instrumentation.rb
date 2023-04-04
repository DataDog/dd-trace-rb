require_relative '../../../core/logging/ext'

module Datadog
  module Tracing
    module Contrib
      module Lograge
        # Instrumentation for Lograge
        module Instrumentation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # Instance methods for configuration
          module InstanceMethods
            def custom_options(event)
              return super unless Datadog.configuration.tracing[:lograge].enabled

              original_custom_options = super(event)

              # Retrieves trace information for current thread
              correlation = Tracing.correlation
              # merge original lambda with datadog context

              datadog_trace_log_hash = {
                # Adds IDs as tags to log output
                dd: {
                  # To preserve precision during JSON serialization, use strings for large numbers
                  trace_id: correlation.trace_id.to_s,
                  span_id: correlation.span_id.to_s,
                  env: correlation.env.to_s,
                  service: correlation.service.to_s,
                  version: correlation.version.to_s
                },
                ddsource: Core::Logging::Ext::DD_SOURCE
              }

              datadog_trace_log_hash.merge(original_custom_options)
            end
          end
        end
      end
    end
  end
end
