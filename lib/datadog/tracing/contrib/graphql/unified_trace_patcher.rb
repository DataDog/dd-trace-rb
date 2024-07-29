# frozen_string_literal: true

require_relative 'unified_trace' if Gem.loaded_specs['graphql'] && Gem.loaded_specs['graphql'].version >= Gem::Version.new('2.0.19')

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        # Provides instrumentation for `graphql` through the GraphQL's tracing with methods defined in UnifiedTrace
        module UnifiedTracePatcher
          module_function

          def patch!(schemas, options)
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
