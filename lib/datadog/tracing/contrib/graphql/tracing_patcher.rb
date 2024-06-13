# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        # Provides instrumentation for `graphql` through the GraphQL's tracing
        module TracingPatcher
          module_function

          def patch!(schemas, options)
            if schemas.empty?
              ::GraphQL::Schema.tracer(::GraphQL::Tracing::DataDogTracing.new(**options))
            else
              schemas.each do |schema|
                if schema.respond_to? :use
                  schema.use(::GraphQL::Tracing::DataDogTracing, **options)
                else
                  Datadog.logger.warn("Unable to patch #{schema}: Please migrate to class-based schema.")
                end
              end
            end
          end
        end
      end
    end
  end
end
