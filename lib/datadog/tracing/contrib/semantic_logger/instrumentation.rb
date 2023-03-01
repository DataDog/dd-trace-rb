require_relative '../../../core/logging/ext'

module Datadog
  module Tracing
    module Contrib
      module SemanticLogger
        # Instrumentation for SemanticLogger
        module Instrumentation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # Instance methods for configuration
          module InstanceMethods
            def log(log, message = nil, progname = nil, &block)
              return super unless Datadog.configuration.tracing[:semantic_logger].enabled

              original_named_tags = log.named_tags || {}

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

              # # if the user already has conflicting log_tags
              # # we want them to clobber ours, because we should allow them to override
              # # if needed.
              log.named_tags = datadog_trace_log_hash.merge(original_named_tags)
              super(log, message, progname, &block)
            end
          end
        end
      end
    end
  end
end
