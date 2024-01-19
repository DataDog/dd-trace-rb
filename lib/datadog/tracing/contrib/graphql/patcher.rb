require_relative '../analytics'
require_relative '../patcher'

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
            schemas = configuration[:schemas]

            if schemas.nil?
              ::GraphQL::Schema.tracer(::GraphQL::Tracing::DataDogTracing.new(**trace_options))
            else
              schemas.each do |schema|
                schema.use(::GraphQL::Tracing::DataDogTracing, **trace_options)
              end
            end
          end

          def trace_options
            {
              service: configuration[:service_name],
              analytics_enabled: configuration[:analytics_enabled],
              analytics_sample_rate: configuration[:analytics_sample_rate]
            }
          end

          def configuration
            Datadog.configuration.tracing[:graphql]
          end
        end
      end
    end
  end
end
