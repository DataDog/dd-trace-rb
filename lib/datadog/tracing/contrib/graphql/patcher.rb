# frozen_string_literal: true

require_relative '../analytics'
require_relative '../patcher'
require_relative 'tracing_patcher'
require_relative 'trace_patcher'
require_relative 'unified_trace_patcher'

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        # Provides instrumentation for `graphql` through the GraphQL tracing framework
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            if configuration[:with_deprecated_tracer]
              TracingPatcher.patch!(schemas, trace_options)
            elsif Integration.trace_supported?
              if configuration[:with_unified_tracer]
                UnifiedTracePatcher.patch!(schemas, trace_options)
              else
                TracePatcher.patch!(schemas, trace_options)
              end
            else
              Datadog.logger.warn(
                "GraphQL version (#{target_version}) does not support GraphQL::Tracing::DataDogTrace"\
                'or Datadog::Tracing::Contrib::GraphQL::UnifiedTrace.'\
                'Falling back to GraphQL::Tracing::DataDogTracing.'
              )
              TracingPatcher.patch!(schemas, trace_options)
            end
          end

          def trace_options
            {
              service: configuration[:service_name],
              analytics_enabled: Contrib::Analytics.enabled?(configuration[:analytics_enabled]),
              analytics_sample_rate: configuration[:analytics_sample_rate]
            }
          end

          def configuration
            Datadog.configuration.tracing[:graphql]
          end

          def schemas
            configuration[:schemas]
          end
        end
      end
    end
  end
end
