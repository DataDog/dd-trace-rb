# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        # Provides instrumentation for `graphql` through the GraphQL's tracing with methods defined in UnifiedTrace
        module UnifiedTracePatcher
          module_function

          def patch!(schemas, options)
            require_relative 'unified_trace'
            if schemas.empty?
              ::GraphQL::Schema.trace_with(UnifiedTrace, **options)
            else
              schemas.each do |schema|
                schema.trace_with(UnifiedTrace, **options)
              end
            end
          end
        end
      end
    end
  end
end
