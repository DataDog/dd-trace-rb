# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        # Provides instrumentation for `graphql` through with GraphQL's trace
        module TracePatcher
          module_function

          def patch!(schemas, options)
            if schemas.empty?
              ::GraphQL::Schema.trace_with(::GraphQL::Tracing::DataDogTrace, **options)
            else
              schemas.each do |schema|
                schema.trace_with(::GraphQL::Tracing::DataDogTrace, **options)
              end
            end
          end
        end
      end
    end
  end
end
