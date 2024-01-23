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

            if schemas.empty?
              ::GraphQL::Schema.tracer(::GraphQL::Tracing::DataDogTracing.new(**trace_options))
            else
              schemas.each do |schema|
                if schema.respond_to? :use
                  schema.use(::GraphQL::Tracing::DataDogTracing, **trace_options)
                else
                  Datadog.logger.warn("Unable to patch #{schema}, please migrate to class-based schema.")
                end
              end
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
        end
      end
    end
  end
end
